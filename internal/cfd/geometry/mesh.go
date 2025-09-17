package geometry

import (
	"github.com/chewxy/math32"
	"math"
)

type MeshDefinition interface {
	Resolve() *Mesh
	GetBoundaries() []string
}

const InternalBoundary = -1

type Mesh struct {
	// === FUNDAMENTAL (starting point) ===
	VerticesX, VerticesY []float32 // vertex coords (deduplicated)
	VertexIndices        []int     // vertex indices for each face (CCW)
	FaceStarts           []int     // CSR: where each cell's face list starts
	FaceMarkers          []int     // -1 = internal, 0+ = boundary

	// boundary data required from the definition
	Bounds     Rectangle
	Boundaries []string // named boundaries corresponding to FaceMarkers

	// === GEOMETRIC PROPERTIES ===
	// face geometry
	FaceAreas                  []float32
	FaceNormalsX, FaceNormalsY []float32

	// cell geometry
	CentroidsX, CentroidsY []float32
	CellVolumes            []float32

	// === CONNECTIVITY PROPERTIES ===
	// connectivity data
	NeighbourIndices []int // 0+ = internal, -1- = boundary

	// connectivity geometry
	ConnectivityVectorsX, ConnectivityVectorsY []float32

	ConnectionDistances      []float32
	FaceInterpolationWeights []float32

	// TODO delete these, keeping structured happy for now
	NeighbourTypes, NeighbourStarts []int
}

func (m *Mesh) NumCells() int {
	return len(m.CentroidsX)
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
		cX, cY := m.CentroidsX[i], m.CentroidsY[i]
		distSqd := (point.X-cX)*(point.X-cX) + (point.Y-cY)*(point.Y-cY)

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

func (m *Mesh) ForEachInternal(fn func(i, j, face int)) {
	for i := range m.NumCells() {
		for f := m.FaceStarts[i]; f < m.FaceStarts[i+1]; f++ {
			j := m.NeighbourIndices[f]
			if j >= 0 {
				fn(i, j, f)
			}
		}
	}
}

func (m *Mesh) ForEachBoundary(fn func(i, bIdx, face int)) {
	for i := range m.NumCells() {
		for f := m.FaceStarts[i]; f < m.FaceStarts[i+1]; f++ {
			j := m.NeighbourIndices[f]
			if j < 0 {
				bIdx := -j - 1
				fn(i, bIdx, f)
			}
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
func dedupVertices(verticesX, verticesY []float32, tolerance float32) (
	dedupX, dedupY []float32, indexMap []int) {
	var minX, maxX, minY, maxY float32 = math.MaxFloat32, -math.MaxFloat32, math.MaxFloat32, -math.MaxFloat32

	for i := range verticesX {
		minX, maxX = min(minX, verticesX[i]), max(maxX, verticesX[i])
		minY, maxY = min(minY, verticesY[i]), max(maxY, verticesY[i])
	}

	maxRange := max(maxX-minX, maxY-minY)
	scale := 1 / (maxRange * tolerance) // how much to multiply our vertices by before casting as integers

	dedupMap := make(map[[2]int]int)
	indexMap = make([]int, len(verticesX))

	for i := range verticesX {
		key := [2]int{int(verticesX[i] * scale), int(verticesY[i] * scale)}

		if existingIdx, found := dedupMap[key]; found {
			indexMap[i] = existingIdx
		} else {
			newIdx := len(dedupX)
			dedupMap[key] = newIdx
			indexMap[i] = newIdx
			dedupX = append(dedupX, verticesX[i])
			dedupY = append(dedupY, verticesY[i])
		}
	}

	return dedupX, dedupY, indexMap
}

func remapVertexIndices(vertexIndices, indexMap []int) []int {
	newVertexIndices := make([]int, len(vertexIndices))

	for i, vIdx := range vertexIndices {
		newVertexIndices[i] = indexMap[vIdx]
	}

	return newVertexIndices
}

func calculateCellGeometry(verticesX, verticesY []float32, vertexIndices, faceStarts []int) (
	cellVolumes, centroidsX, centroidsY []float32) {
	nCells := len(faceStarts) - 1
	cellVolumes, centroidsX, centroidsY = make([]float32, nCells), make([]float32, nCells), make([]float32, nCells)

	for i := range nCells {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]
		numVertices := endIdx - startIdx

		var totalX, totalY, shoelace float32
		for fi := startIdx; fi < endIdx; fi++ {
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			totalX += verticesX[vi]
			totalY += verticesY[vi]
			shoelace += verticesX[vi]*verticesY[nextVi] - verticesX[nextVi]*verticesY[vi]
		}

		centroidsX[i] = totalX / float32(numVertices)
		centroidsY[i] = totalY / float32(numVertices)
		cellVolumes[i] = shoelace / 2

		if cellVolumes[i] < 0 {
			panic("calculateCellGeometry fatal: cannot have a negative volume")
		}
	}

	return
}

func calculateFaceGeometry(verticesX, verticesY []float32, vertexIndices, faceStarts []int) (
	faceAreas, faceNormalsX, faceNormalsY []float32) {
	nCells := len(faceStarts) - 1
	nFaces := len(vertexIndices)

	faceAreas, faceNormalsX, faceNormalsY = make([]float32, nFaces), make([]float32, nFaces), make([]float32, nFaces)

	for i := range nCells {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]

		for fi := startIdx; fi < endIdx; fi++ {
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			dX, dY := verticesX[nextVi]-verticesX[vi], verticesY[nextVi]-verticesY[vi]

			faceAreas[fi] = math32.Sqrt((dX)*(dX) + (dY)*(dY)) // magnitude of vector AND normal

			// CCW normal of (dX, dY) = (dY, -dX)
			faceNormalsX[fi], faceNormalsY[fi] = dY/faceAreas[fi], -dX/faceAreas[fi]
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
	centroidsX, centroidsY []float32,
	neighbourIndices []int,
	verticesX, verticesY []float32,
	vertexIndices, faceStarts []int,
) (connectionVectorsX, connectionVectorsY, connectionDistances, faceInterpolationWeights []float32) {
	connectionVectorsX = make([]float32, len(neighbourIndices))
	connectionVectorsY = make([]float32, len(neighbourIndices))
	connectionDistances = make([]float32, len(neighbourIndices))
	faceInterpolationWeights = make([]float32, len(neighbourIndices))

	for i := range len(centroidsX) {
		startIdx, endIdx := faceStarts[i], faceStarts[i+1]
		cX, cY := centroidsX[i], centroidsY[i]

		for fi := startIdx; fi < endIdx; fi++ {
			ni := neighbourIndices[fi]
			vi := vertexIndices[fi]
			nextFi := startIdx + (fi-startIdx+1)%(endIdx-startIdx)
			nextVi := vertexIndices[nextFi]

			f1X, f1Y := verticesX[vi], verticesY[vi]               // face vector start point
			fX, fY := verticesX[nextVi]-f1X, verticesY[nextVi]-f1Y // face vector

			if ni < 0 {
				fcX, fcY := f1X+0.5*fX, f1Y+0.5*fY // face centroid
				bdX, bdY := fcX-cX, fcY-cY         // boundary dX/Y

				connectionDistances[fi] = math32.Sqrt(bdX*bdX + bdY*bdY)
				connectionVectorsX[fi] = bdX / connectionDistances[fi]
				connectionVectorsY[fi] = bdY / connectionDistances[fi]
				faceInterpolationWeights[fi] = 1 // boundary
				continue
			}

			dX, dY := centroidsX[ni]-cX, centroidsY[ni]-cY

			connectionDistances[fi] = math32.Sqrt(dX*dX + dY*dY)
			connectionVectorsX[fi] = dX / connectionDistances[fi]
			connectionVectorsY[fi] = dY / connectionDistances[fi]

			// Cramers rule for finding intersection:
			// [dx - fx]t1 = [Fx - Cx]
			// [dy - fy]t2 = [Fy - Cy]
			// is what we are trying to solve

			det := (dX*-fY - dY*-fX)
			if math32.Abs(det) < 1e-9 {
				panic("calculateConnectivityGeometry: face and centroid vectors are considered parallel")
			}

			t1 := (dX*(f1Y-cY) - dY*(f1X-cX)) / det
			t2 := ((f1X-cX)*-fY - (f1Y-cY)*-fX) / det

			if t1 < 0 || t1 > 1 || t2 < 0 || t2 > 1 {
				panic("calculateConnectivityGeometry: connection vector and face vector do not intersect")
			}

			iX, iY := cX+t1*dX, cY+t1*dY // intersection coords
			fdX, fdY := iX-cX, iY-cY     // centroid -> intersection vector
			faceDistance := math32.Sqrt(fdX*fdX + fdY*fdY)
			faceInterpolationWeights[fi] = faceDistance / connectionDistances[fi]
		}
	}

	return
}
