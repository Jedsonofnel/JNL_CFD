package geometry

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/chewxy/math32"
	"math"
)

type Vec2 linalg.Vec2

type MeshDefinition interface {
	Resolve() *Mesh
	GetBoundaries() []string
}

const InternalBoundary = -1

type Mesh struct {
	// === FUNDAMENTAL (starting point) ===
	Vertices      []Vec2 // vertex coords (deduplicated)
	VertexIndices []int  // vertex indices for each face (CCW)
	FaceStarts    []int  // CSR: where each cell's face list starts
	FaceMarkers   []int  // -1 = internal, 0+ = boundary

	// boundary data required from the definition
	Bounds     Rectangle
	Boundaries []string // named boundaries corresponding to FaceMarkers

	// === GEOMETRIC PROPERTIES ===
	// face geometry
	FaceAreas   []float32
	FaceNormals []Vec2

	// cell geometry
	Centroids   []Vec2
	CellVolumes []float32

	// === CONNECTIVITY PROPERTIES ===
	// connectivity data
	NeighbourIndices []int // 0+ = internal, -1- = boundary

	// connectivity geometry
	ConnectivityVectors []Vec2

	ConnectionDistances      []float32
	FaceInterpolationWeights []float32
}

func (m *Mesh) NumCells() int {
	return len(m.Centroids)
}

func (m *Mesh) NumNeighbours() int {
	return len(m.NeighbourIndices)
}

func (m *Mesh) NumBoundaries() int {
	accumulator := 0
	for _, ni := range m.NeighbourIndices {
		if ni < 0 {
			accumulator++
		}
	}

	return accumulator
}

func (m *Mesh) FindClosestCell(point Vec2) int {
	m.Bounds.EnforceContains(point.X, point.Y)
	minDistSqd := float32(math.MaxFloat32)
	closestCell := -1

	for i := range m.NumCells() {
		c := m.Centroids[i]
		distSqd := (point.X-c.X)*(point.X-c.X) + (point.Y-c.Y)*(point.Y-c.Y)

		if distSqd < minDistSqd {
			minDistSqd = distSqd
			closestCell = i
		}
	}

	return closestCell
}

func (m *Mesh) ForEachCell(fn func(i int)) {
	for i := range m.NumCells() {
		fn(i)
	}
}

func (m *Mesh) ForEachConnection(fn func(i, j, face int)) {
	for i := range m.NumCells() {
		for f := m.FaceStarts[i]; f < m.FaceStarts[i+1]; f++ {
			j := m.NeighbourIndices[f]
			fn(i, j, f)
		}
	}
}

// mesh generation functions
// starting with polygon data the steps go:
// 1 -> deduplicate vertices
// 2 -> remap face indices
// 3 -> calculate face geometry
// 4 -> calculate cell geometry
// 5 -> derive connectivity
// 6 -> calculate connectivity geometry
func dedupVertices(vertices []Vec2, tolerance float32) (
	dedup []Vec2, indexMap []int) {
	var minX, maxX, minY, maxY float32 = math.MaxFloat32, -math.MaxFloat32, math.MaxFloat32, -math.MaxFloat32

	for i := range vertices {
		minX, maxX = min(minX, vertices[i].X), max(maxX, vertices[i].X)
		minY, maxY = min(minY, vertices[i].Y), max(maxY, vertices[i].Y)
	}

	maxRange := max(maxX-minX, maxY-minY)
	scale := 1 / (maxRange * tolerance) // how much to multiply our vertices by before casting as integers

	dedupMap := make(map[[2]int]int)
	indexMap = make([]int, len(vertices))

	for i := range vertices {
		key := [2]int{int(vertices[i].X * scale), int(vertices[i].Y * scale)}

		if existingIdx, found := dedupMap[key]; found {
			indexMap[i] = existingIdx
		} else {
			newIdx := len(dedup)
			dedupMap[key] = newIdx
			indexMap[i] = newIdx
			dedup = append(dedup, vertices[i])
		}
	}

	return dedup, indexMap
}

func remapVertexIndices(vertexIndices, indexMap []int) []int {
	newVertexIndices := make([]int, len(vertexIndices))

	for i, vIdx := range vertexIndices {
		newVertexIndices[i] = indexMap[vIdx]
	}

	return newVertexIndices
}

func calculateCellGeometry(
	vertices []Vec2,
	vertexIndices, faceStarts []int,
) (cellVolumes []float32, centroids []Vec2) {
	nCells := len(faceStarts) - 1
	cellVolumes = make([]float32, nCells)
	centroids = make([]Vec2, nCells)

	for i := range nCells {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]
		numVertices := endIdx - startIdx

		var totalX, totalY, shoelace float32
		for fi := startIdx; fi < endIdx; fi++ {
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			totalX += vertices[vi].X
			totalY += vertices[vi].Y
			shoelace += vertices[vi].X*vertices[nextVi].Y - vertices[nextVi].X*vertices[vi].Y
		}

		centroids[i].X = totalX / float32(numVertices)
		centroids[i].Y = totalY / float32(numVertices)
		cellVolumes[i] = shoelace / 2

		if cellVolumes[i] < 0 {
			panic("calculateCellGeometry fatal: cannot have a negative volume")
		}
	}

	return
}

func calculateFaceGeometry(vertices []Vec2, vertexIndices, faceStarts []int) (
	faceAreas []float32, faceNormals []Vec2) {
	nCells := len(faceStarts) - 1
	nFaces := len(vertexIndices)

	faceAreas, faceNormals = make([]float32, nFaces), make([]Vec2, nFaces)

	for i := range nCells {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]

		for fi := startIdx; fi < endIdx; fi++ {
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			dX, dY := vertices[nextVi].X-vertices[vi].X, vertices[nextVi].Y-vertices[vi].Y

			faceAreas[fi] = math32.Sqrt((dX)*(dX) + (dY)*(dY)) // magnitude of vector AND normal

			// CCW normal of (dX, dY) = (dY, -dX)
			faceNormals[fi].X = dY / faceAreas[fi]
			faceNormals[fi].Y = -dX / faceAreas[fi]
		}
	}
	return
}

func deriveConnectivity(vertexIndices, faceStarts, faceMarkers []int) (neighbourIndices []int) {
	// algorithm - edge based hashing.
	// build up map of canonical edge(v1, v2) to cell indices (one loop)
	// loop through again to construct neighbourIndices
	neighbourIndices = make([]int, len(faceMarkers))

	edgeMap := make(map[[2]int][][2]int)
	for i := range len(faceStarts) - 1 {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]

		localFaceIdx := 0
		for fi := startIdx; fi < endIdx; fi++ {
			// plus one comes from wanting to get the next one
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)

			v1, v2 := vertexIndices[fi], vertexIndices[nextFi]
			key := [2]int{min(v1, v2), max(v1, v2)}

			edgeMap[key] = append(edgeMap[key], [2]int{i, localFaceIdx})
			localFaceIdx++
		}
	}

	for _, cells := range edgeMap {
		if len(cells) == 1 {
			idx := faceStarts[cells[0][0]] + cells[0][1]
			neighbourIndices[idx] = -1
			continue
		}

		if len(cells) > 2 {
			panic("deriveConnectivity: more than 2 cells to a face is not possible")
		}

		// ie 0 = cellId, 1 = localFaceID
		cell0, cell1 := cells[0], cells[1]

		idx0 := faceStarts[cell0[0]] + cell0[1]
		idx1 := faceStarts[cell1[0]] + cell1[1]

		neighbourIndices[idx0] = cell1[0]
		neighbourIndices[idx1] = cell0[0]
	}

	// update neighbourIndices for boundaries to increment downwards
	boundaryIncr := 0
	for i, ni := range neighbourIndices {
		if ni == -1 {
			neighbourIndices[i] = -1 - boundaryIncr
			boundaryIncr++
		}
	}

	return
}

func calculateConnectivityGeometry(
	centroids []Vec2,
	neighbourIndices []int,
	vertices []Vec2,
	vertexIndices, faceStarts []int,
) (connectionVectors []Vec2, connectionDistances, faceInterpolationWeights []float32) {
	connectionVectors = make([]Vec2, len(neighbourIndices))
	connectionDistances = make([]float32, len(neighbourIndices))
	faceInterpolationWeights = make([]float32, len(neighbourIndices))

	for i := range len(centroids) {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]
		c := centroids[i]

		for fi := startIdx; fi < endIdx; fi++ {
			ni := neighbourIndices[fi]
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			f1 := vertices[vi] // face vector start point

			fX, fY := vertices[nextVi].X-f1.X, vertices[nextVi].Y-f1.Y // face vector

			if ni < 0 {
				fcX, fcY := f1.X+0.5*fX, f1.Y+0.5*fY // face centroid
				bdX, bdY := fcX-c.X, fcY-c.Y         // boundary dX/Y

				connectionDistances[fi] = math32.Sqrt(bdX*bdX + bdY*bdY)
				connectionVectors[fi].X = bdX / connectionDistances[fi]
				connectionVectors[fi].Y = bdY / connectionDistances[fi]
				faceInterpolationWeights[fi] = 1 // boundary
				continue
			}

			dX, dY := centroids[ni].X-c.X, centroids[ni].Y-c.Y

			connectionDistances[fi] = math32.Sqrt(dX*dX + dY*dY)
			connectionVectors[fi].X = dX / connectionDistances[fi]
			connectionVectors[fi].Y = dY / connectionDistances[fi]

			// Cramers rule for finding intersection:
			// [dx - fx]t1 = [Fx - Cx]
			// [dy - fy]t2 = [Fy - Cy]
			// is what we are trying to solve

			det := (dX*-fY - dY*-fX)
			if math32.Abs(det) < 1e-9 {
				panic("calculateConnectivityGeometry: face and centroid vectors are considered parallel")
			}

			t1 := (dX*(f1.Y-c.Y) - dY*(f1.X-c.X)) / det
			t2 := ((f1.X-c.X)*-fY - (f1.Y-c.Y)*-fX) / det

			if t1 < 0 || t1 > 1 || t2 < 0 || t2 > 1 {
				panic("calculateConnectivityGeometry: connection vector and face vector do not intersect")
			}

			iX, iY := c.X+t1*dX, c.Y+t1*dY // intersection coords
			fdX, fdY := iX-c.X, iY-c.Y     // centroid -> intersection vector
			faceDistance := math32.Sqrt(fdX*fdX + fdY*fdY)
			faceInterpolationWeights[fi] = faceDistance / connectionDistances[fi]
		}
	}

	return
}
