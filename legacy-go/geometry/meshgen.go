package geometry

import (
	"math"
	"strconv"

	"jedn.dev/jnlcfd/geometry/triangle"
)

//
// Important types for using Triangle.c
//

type PSLG struct {
	Points   []Vec2
	Segments []Segment
	Holes    []Vec2
	Regions  []Region
}

type Segment struct {
	P0, P1 int // point indices
	Marker int
}

type Region struct {
	Point   Vec2
	ID      int
	MaxArea float64
}

//
// Converts to C types and calls CGO wrapper triangle package
//

// MeshDomain runs Triangle.c on the domain and returns a fully qualified *Mesh
func MeshDomain(domain *Domain, options string) (*Mesh, error) {
	pslg := domain.toPSLG()
	input := pslgToTriangleInput(pslg) // Pending

	output, err := triangle.Triangulate(input, options)
	if err != nil {
		return nil, err
	}

	return triangleOutputToMesh(output, domain), nil
}

func MeshWithArea(domain *Domain, maxArea, minAngle float64) (*Mesh, error) {
	if minAngle <= 0 {
		minAngle = 30
	}
	opts := buildTriangleOptions(minAngle, maxArea)
	return MeshDomain(domain, opts)
}

func MeshWithCells(domain *Domain, targetCells int, minAngle float64) (*Mesh, error) {
	maxArea := domain.meshableArea() / float64(targetCells)
	return MeshWithArea(domain, maxArea, minAngle)
}

func MeshWithResolution(domain *Domain, cellsPerUnit, minAngle float64) (*Mesh, error) {
	h := 1.0 / cellsPerUnit
	maxArea := equilateralArea(h)
	return MeshWithArea(domain, maxArea, minAngle)
}

func MeshWithEdgeLength(domain *Domain, edgeLength, minAngle float64) (*Mesh, error) {
	maxArea := equilateralArea(edgeLength)
	return MeshWithArea(domain, maxArea, minAngle)
}

func equilateralArea(h float64) float64 {
	return (math.Sqrt(3) / 4.0) * h * h
}

func buildTriangleOptions(quality float64, maximumArea float64) string {
	result := "pzQA"

	if quality > 0 {
		result += "q"
		result += strconv.FormatFloat(quality, 'f', -1, 64)
	}

	if maximumArea > 0 {
		result += "a"
		result += strconv.FormatFloat(maximumArea, 'f', -1, 64)
	}

	return result
}

//
// Implementation details
//

// pslgToTriangleInput converts a PSLG to Triangle.c input format
func pslgToTriangleInput(pslg PSLG) triangle.Input {
	input := triangle.Input{}

	// Convert points: Vec2 → [x0, y0, x1, y1, ...]
	input.Points = make([]float64, len(pslg.Points)*2)
	for i, p := range pslg.Points {
		input.Points[i*2+0] = p.X
		input.Points[i*2+1] = p.Y
	}

	// Convert segments: Segment → [p0, p1, p2, p3, ...]
	input.Segments = make([]int, len(pslg.Segments)*2)
	input.SegmentMarkers = make([]int, len(pslg.Segments))
	for i, seg := range pslg.Segments {
		input.Segments[i*2+0] = seg.P0
		input.Segments[i*2+1] = seg.P1
		input.SegmentMarkers[i] = seg.Marker
	}

	// Convert regions: Region → [x, y, id, maxArea, ...]
	input.Regions = make([]float64, len(pslg.Regions)*4)
	for i, reg := range pslg.Regions {
		input.Regions[i*4+0] = reg.Point.X
		input.Regions[i*4+1] = reg.Point.Y
		input.Regions[i*4+2] = float64(reg.ID)
		input.Regions[i*4+3] = reg.MaxArea
	}

	// Convert holes: Vec2 → [hx0, hy0, hx1, hy1, ...]
	input.Holes = make([]float64, len(pslg.Holes)*2)
	for i, h := range pslg.Holes {
		input.Holes[i*2+0] = h.X
		input.Holes[i*2+1] = h.Y
	}

	return input
}

// triangleOutputToMesh handles parsing triangle output and converting it into
// the CFD-ready *Mesh data structure
func triangleOutputToMesh(output *triangle.Output, domain *Domain) *Mesh {
	numTris := len(output.Triangles) / 3

	// convert vertices
	numVerts := len(output.Points) / 2
	vertices := make([]Vec2, numVerts)
	for i := range numVerts {
		vertices[i] = Vec2{
			X: output.Points[i*2+0],
			Y: output.Points[i*2+1],
		}
	}

	// deduplicate (Triangle.c might duplicate at boundaries)
	dedupVerts, indexMap := dedupVertices(vertices, 1e-6)

	// Build CSR format for triangles
	vertexIndices := make([]int, numTris*3)
	faceStarts := make([]int, numTris+1)
	for i := range numTris {
		faceStarts[i] = i * 3
		vertexIndices[i*3+0] = indexMap[output.Triangles[i*3+0]]
		vertexIndices[i*3+1] = indexMap[output.Triangles[i*3+1]]
		vertexIndices[i*3+2] = indexMap[output.Triangles[i*3+2]]
	}
	faceStarts[numTris] = numTris * 3

	cellVolumes, centroids := calculateCellGeometry(dedupVerts, vertexIndices, faceStarts)

	segmentMarkers := buildSegmentMarkerMap(output, indexMap)
	faceMarkers := buildFaceMarkers(segmentMarkers, vertexIndices, faceStarts)

	// build region IDs
	cellRegions := make([]int, numTris)
	for i := range numTris {
		if len(output.TriangleAttributes) > 0 {
			cellRegions[i] = int(output.TriangleAttributes[i])
		}
	}

	connections,
		faceAreas,
		faceNormals,
		faceCentroids,
		connectionVecs,
		connectionDists,
		interpWeights := buildConnectionGeometry(
		vertexIndices,
		faceStarts,
		dedupVerts,
		centroids,
		faceMarkers,
	)

	meshRegionNames := make(map[int]string)
	for name, id := range domain.regionNames {
		meshRegionNames[id] = name
	}

	meshBoundaryNames := make(map[int]string)
	for name, marker := range domain.boundaryNames {
		meshBoundaryNames[marker] = name
	}

	mesh := &Mesh{
		Vertices:    dedupVerts,
		Connections: connections,

		FaceAreas:       faceAreas,
		FaceNormals:     faceNormals,
		FaceCentroids:   faceCentroids,
		ConnectionVecs:  connectionVecs,
		ConnectionDists: connectionDists,
		InterpWeights:   interpWeights,

		CellRegions: cellRegions,
		Centroids:   centroids,
		CellVolumes: cellVolumes,

		VertexIndices: vertexIndices,
		FaceStarts:    faceStarts,

		BoundaryNames: meshBoundaryNames,
		RegionNames:   meshRegionNames,
		Domain:        domain,
	}

	mesh.buildBoundaryFaces()
	mesh.buildNonOrthogonalCoeffs()

	return mesh
}

//
// Polgyon soup to mesh helpers
//

// dedupVertices deduplicates vertices according to a certain tolerance
// to ensure that the output of some polygon soup is deduplicated.
func dedupVertices(vertices []Vec2, tolerance float64) (
	dedup []Vec2, indexMap []int) {
	var minX, maxX, minY, maxY float64 = math.MaxFloat64, -math.MaxFloat64, math.MaxFloat64, -math.MaxFloat64

	for i := range vertices {
		minX, maxX = min(minX, vertices[i].X), max(maxX, vertices[i].X)
		minY, maxY = min(minY, vertices[i].Y), max(maxY, vertices[i].Y)
	}

	maxRange := max(maxX-minX, maxY-minY)
	scale := 0.5 / (maxRange * tolerance) // how much to multiply our vertices by before casting as integers

	dedupMap := make(map[[2]int]int)
	indexMap = make([]int, len(vertices))

	for i := range vertices {
		gridX := int(math.Round(vertices[i].X * scale))
		gridY := int(math.Round(vertices[i].Y * scale))

		// Check this cell and 8 neighbors for nearby vertices
		found := false
		var foundIdx int

		for dx := -1; dx <= 1; dx++ {
			for dy := -1; dy <= 1; dy++ {
				key := [2]int{gridX + dx, gridY + dy}
				if existingIdx, ok := dedupMap[key]; ok {
					existing := dedup[existingIdx]
					dist := math.Sqrt(
						(vertices[i].X-existing.X)*(vertices[i].X-existing.X) +
							(vertices[i].Y-existing.Y)*(vertices[i].Y-existing.Y))

					if dist < tolerance*maxRange {
						found = true
						foundIdx = existingIdx
						break
					}
				}
			}
			if found {
				break
			}
		}

		if found {
			indexMap[i] = foundIdx
		} else {
			key := [2]int{gridX, gridY}
			newIdx := len(dedup)
			dedupMap[key] = newIdx
			indexMap[i] = newIdx
			dedup = append(dedup, vertices[i])
		}
	}

	return dedup, indexMap
}

// calculateCellGeometry calculates cellVolumes and centroids given polygon
// soup in CSR format
func calculateCellGeometry(
	vertices []Vec2,
	vertexIndices,
	faceStarts []int,
) (
	cellVolumes []float64,
	centroids []Vec2,
) {
	nCells := len(faceStarts) - 1

	cellVolumes = make([]float64, nCells)
	centroids = make([]Vec2, nCells)

	for i := range nCells {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]

		var cx, cy, signedArea float64
		for fi := startIdx; fi < endIdx; fi++ {
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			cross := vertices[vi].X*vertices[nextVi].Y - vertices[nextVi].X*vertices[vi].Y
			signedArea += cross
			cx += (vertices[vi].X + vertices[nextVi].X) * cross
			cy += (vertices[vi].Y + vertices[nextVi].Y) * cross
		}
		signedArea /= 2
		cellVolumes[i] = math.Abs(signedArea)
		centroids[i].X = cx / (6 * signedArea)
		centroids[i].Y = cy / (6 * signedArea)

		if signedArea < 0 {
			panic("calculateCellGeometry fatal: cannot have a negative volume")
		}
	}

	return
}

// buildConnectionGeometry creates connections and computes all face
// geometries in one fell swoop.  'tis a mega function
func buildConnectionGeometry(
	vertexIndices []int,
	faceStarts []int,
	vertices []Vec2,
	centroids []Vec2,
	faceMarkers []int,
) (
	connections []Connection,
	faceAreas []float64,
	faceNormals []Vec2,
	faceCentroids []Vec2,
	connectionVecs []Vec2,
	connectionDists []float64,
	interpWeights []float64,
) {
	neighbourIndices := deriveNeighbours(vertexIndices, faceStarts)

	nCells := len(faceStarts) - 1

	// Pre-allocate (estimate: ~1.5x cells for triangles, adjust for other polygons)
	estimatedConnections := len(vertexIndices) / 2
	connections = make([]Connection, 0, estimatedConnections)
	faceAreas = make([]float64, 0, estimatedConnections)
	faceNormals = make([]Vec2, 0, estimatedConnections)
	faceCentroids = make([]Vec2, 0, estimatedConnections)
	connectionVecs = make([]Vec2, 0, estimatedConnections)
	connectionDists = make([]float64, 0, estimatedConnections)
	interpWeights = make([]float64, 0, estimatedConnections)

	// process each cell's faces
	for owner := range nCells {
		startIdx := faceStarts[owner]
		endIdx := faceStarts[owner+1]
		ownerCentroid := centroids[owner]

		for faceIdx := startIdx; faceIdx < endIdx; faceIdx++ {
			neighbour := neighbourIndices[faceIdx]

			// only store internal faces once (lower index is owner)
			if neighbour >= 0 && owner >= neighbour {
				continue
			}

			vi := vertexIndices[faceIdx]
			nextFaceIdx := startIdx + (faceIdx-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFaceIdx]

			v0 := vertices[vi]
			v1 := vertices[nextVi]

			// get boundary marker if neighbour < 0
			if neighbour < 0 {
				neighbour = -1 * faceMarkers[faceIdx] // multiply by -1 so it's negative
			}

			// Add connection
			connections = append(connections, Connection{
				Owner:     int32(owner),
				Neighbour: int32(neighbour),
			})

			dx := v1.X - v0.X
			dy := v1.Y - v0.Y
			length := math.Sqrt(dx*dx + dy*dy)

			faceAreas = append(faceAreas, length)

			fc := Vec2{
				X: (v0.X + v1.X) / 2.0,
				Y: (v0.Y + v1.Y) / 2.0,
			}
			faceCentroids = append(faceCentroids, fc)

			// Outward normal (perpendicular to edge, CCW rotation gives outward)
			nx := dy / length
			ny := -dx / length

			// Ensure normal points from owner toward neighbour/boundary
			toFaceX := fc.X - ownerCentroid.X
			toFaceY := fc.Y - ownerCentroid.Y

			if nx*toFaceX+ny*toFaceY < 0 {
				nx = -nx
				ny = -ny
			}

			faceNormals = append(faceNormals, Vec2{X: nx, Y: ny})

			if neighbour < 0 {
				// Boundary face - distance to face centroid
				distX := fc.X - ownerCentroid.X
				distY := fc.Y - ownerCentroid.Y
				dist := math.Sqrt(distX*distX + distY*distY)

				connectionVecs = append(connectionVecs, Vec2{
					X: fc.X - ownerCentroid.X,
					Y: fc.Y - ownerCentroid.Y,
				})

				connectionDists = append(connectionDists, dist)
				interpWeights = append(interpWeights, 1.0) // Boundary

				continue
			}

			// Internal face - distance between centroids
			neighbourCentroid := centroids[neighbour]
			distX := neighbourCentroid.X - ownerCentroid.X
			distY := neighbourCentroid.Y - ownerCentroid.Y
			totalDist := math.Sqrt(distX*distX + distY*distY)

			connectionVecs = append(connectionVecs, Vec2{
				X: neighbourCentroid.X - ownerCentroid.X,
				Y: neighbourCentroid.Y - ownerCentroid.Y,
			})

			connectionDists = append(connectionDists, totalDist)

			// Interpolation weight using line-face intersection
			// This is your Cramer's rule approach - more accurate than simple ratio
			weight := calculateInterpWeight(ownerCentroid, neighbourCentroid, v0, v1)
			interpWeights = append(interpWeights, weight)
		}
	}

	return
}

// deriveNeighbours builds neighbour array using edge-based hashing (polygon-agnostic)
func deriveNeighbours(vertexIndices, faceStarts []int) []int {
	neighbourIndices := make([]int, len(vertexIndices))

	// Build edge map: edge → [(cellID, localFaceID), ...]
	edgeMap := make(map[[2]int][][2]int)

	nCells := len(faceStarts) - 1
	for cellID := range nCells {
		startIdx := faceStarts[cellID]
		endIdx := faceStarts[cellID+1]

		localFaceID := 0
		for faceIdx := startIdx; faceIdx < endIdx; faceIdx++ {
			nextFaceIdx := startIdx + (faceIdx-startIdx+1)%(endIdx-startIdx)

			v0 := vertexIndices[faceIdx]
			v1 := vertexIndices[nextFaceIdx]

			// Canonical edge representation (min, max)
			edge := [2]int{min(v0, v1), max(v0, v1)}

			edgeMap[edge] = append(edgeMap[edge], [2]int{cellID, localFaceID})
			localFaceID++
		}
	}

	// Build neighbour connections
	for _, cells := range edgeMap {
		if len(cells) == 1 {
			// Boundary face
			cellID := cells[0][0]
			localFaceID := cells[0][1]
			faceIdx := faceStarts[cellID] + localFaceID
			neighbourIndices[faceIdx] = -1
		} else if len(cells) == 2 {
			// Internal face - two cells share this edge
			cell0ID := cells[0][0]
			cell0LocalFace := cells[0][1]
			cell1ID := cells[1][0]
			cell1LocalFace := cells[1][1]

			face0Idx := faceStarts[cell0ID] + cell0LocalFace
			face1Idx := faceStarts[cell1ID] + cell1LocalFace

			neighbourIndices[face0Idx] = cell1ID
			neighbourIndices[face1Idx] = cell0ID
		} else {
			panic("deriveNeighbours: more than 2 cells share an edge (non-manifold mesh)")
		}
	}

	return neighbourIndices
}

// calculateInterpWeight finds where connection line intersects face
// Returns ratio: distance(owner→face) / distance(owner→neighbour)
func calculateInterpWeight(ownerCentroid, neighbourCentroid, faceV0, faceV1 Vec2) float64 {
	// Connection vector
	dX := neighbourCentroid.X - ownerCentroid.X
	dY := neighbourCentroid.Y - ownerCentroid.Y

	// Face vector
	fX := faceV1.X - faceV0.X
	fY := faceV1.Y - faceV0.Y

	// Solve for intersection using Cramer's rule:
	// ownerCentroid + t1*d = faceV0 + t2*f
	// Where t1 is the parameter along connection, t2 along face

	det := dX*(-fY) - dY*(-fX)
	if math.Abs(det) < 1e-9 {
		// Parallel - shouldn't happen in valid mesh, use simple ratio
		fcX := (faceV0.X + faceV1.X) / 2.0
		fcY := (faceV0.Y + faceV1.Y) / 2.0
		distToFace := math.Sqrt((fcX-ownerCentroid.X)*(fcX-ownerCentroid.X) +
			(fcY-ownerCentroid.Y)*(fcY-ownerCentroid.Y))
		totalDist := math.Sqrt(dX*dX + dY*dY)
		return distToFace / totalDist
	}

	t1 := (fX*(faceV0.Y-ownerCentroid.Y) - fY*(faceV0.X-ownerCentroid.X)) / det

	// t1 should be in [0, 1] for valid intersection
	if t1 < 0 || t1 > 1 {
		// Shouldn't happen in valid mesh - use face centroid fallback
		fcX := (faceV0.X + faceV1.X) / 2.0
		fcY := (faceV0.Y + faceV1.Y) / 2.0
		distToFace := math.Sqrt((fcX-ownerCentroid.X)*(fcX-ownerCentroid.X) +
			(fcY-ownerCentroid.Y)*(fcY-ownerCentroid.Y))
		totalDist := math.Sqrt(dX*dX + dY*dY)
		return distToFace / totalDist
	}

	return t1
}

// buildSegmentMarkerMap creates edge→marker lookup from Triangle segments
func buildSegmentMarkerMap(output *triangle.Output, indexMap []int) map[[2]int]int {
	markers := make(map[[2]int]int)
	numSegs := len(output.Segments) / 2

	for i := range numSegs {
		p0 := indexMap[output.Segments[i*2+0]]
		p1 := indexMap[output.Segments[i*2+1]]

		// in case of degenerate cases - these have been skipped by dedupe
		if p0 == p1 {
			continue
		}

		key := [2]int{min(p0, p1), max(p0, p1)}

		if len(output.SegmentMarkers) > i {
			markers[key] = output.SegmentMarkers[i]
		}
	}

	return markers
}

// buildFaceMarkers maps segment markers to faces (polygon-agnostic)
func buildFaceMarkers(segmentMarkers map[[2]int]int, vertexIndices, faceStarts []int) []int {
	markers := make([]int, len(vertexIndices))

	nCells := len(faceStarts) - 1
	for cellID := range nCells {
		startIdx := faceStarts[cellID]
		endIdx := faceStarts[cellID+1]

		for faceIdx := startIdx; faceIdx < endIdx; faceIdx++ {
			nextFaceIdx := startIdx + (faceIdx-startIdx+1)%(endIdx-startIdx)

			v0 := vertexIndices[faceIdx]
			v1 := vertexIndices[nextFaceIdx]

			edge := [2]int{min(v0, v1), max(v0, v1)}
			if marker, ok := segmentMarkers[edge]; ok {
				markers[faceIdx] = marker
			}
		}
	}

	return markers
}

//
// Fully derived fields
//

func (m *Mesh) buildBoundaryFaces() {
	if m.BoundaryFaces != nil {
		return // already built
	}

	if m.Connections == nil || m.BoundaryNames == nil {
		panic("buildBoundaryFaces requires Connections and BoundaryFaces")
	}

	m.BoundaryFaces = make(map[string][]int)

	for i, conn := range m.Connections {
		if conn.Neighbour < 0 {
			marker := int(-conn.Neighbour)
			if name, ok := m.BoundaryNames[marker]; ok {
				m.BoundaryFaces[name] = append(m.BoundaryFaces[name], i)
			}
		}
	}
}

func (m *Mesh) buildNonOrthogonalCoeffs() {
	if m.OrthFactors != nil && m.NonOrthDeltas != nil {
		return // already built
	}

	if m.ConnectionVecs == nil || m.FaceNormals == nil {
		panic("buildNonOrthogonalCoeffs requires ConnectionVecs and FaceNormals")
	}

	n := len(m.Connections)
	m.OrthFactors = make([]float64, n)
	m.NonOrthDeltas = make([]Vec2, n)

	for i, fn := range m.FaceNormals {
		d := m.ConnectionDists[i]

		if d < 1e-30 {
			m.OrthFactors[i] = 1.0
			continue
		}

		// Unit vector along connection
		eX := m.ConnectionVecs[i].X / d
		eY := m.ConnectionVecs[i].Y / d

		// Orthogonality factor
		dot := fn.X*eX + fn.Y*eY
		m.OrthFactors[i] = dot

		// Correction vector: Δ = n - (n·e)e
		m.NonOrthDeltas[i] = Vec2{
			X: fn.X - dot*eX,
			Y: fn.Y - dot*eY,
		}
	}
}
