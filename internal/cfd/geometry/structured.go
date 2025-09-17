package geometry

type structuredMesh struct {
	NX         int      `json:"nx"`
	NY         int      `json:"ny"`
	Width      float32  `json:"width"`
	Height     float32  `json:"height"`
	Boundaries []string `json:"boundaries"`
}

func NewStructuredMesh(nX, nY int, width, height float64) MeshDefinition {
	return &structuredMesh{
		NX:         nX,
		NY:         nY,
		Width:      float32(width),
		Height:     float32(height),
		Boundaries: []string{"northBorder", "eastborder", "southBorder", "westBorder"},
	}
}

func (sm *structuredMesh) GetBoundaries() []string {
	return sm.Boundaries
}

// Yes it's super monolithic BUT the data flow is clear and it's more readable as a result
func (sm *structuredMesh) Resolve() *Mesh {
	nCells := sm.NX * sm.NY
	sX, sY := sm.Width/float32(sm.NX), sm.Height/float32(sm.NY)

	bounds := Rectangle{Width: sm.Width, Height: sm.Height}
	boundaries := []string{"northBorder", "eastborder", "southBorder", "westBorder"}

	verticesX := make([]float32, nCells*4)
	verticesY := make([]float32, nCells*4)
	vertexIndices := make([]int, nCells*4)
	faceStarts := make([]int, nCells+1)
	faceMarkers := make([]int, nCells*4)

	vCount := 0
	for i := range sm.NY { // rows
		for j := range sm.NX { // column
			cellIdx := i*sm.NX + j // cell, goes through a column then up a row
			faceStarts[cellIdx] = cellIdx * 4

			// bottom face
			verticesX[vCount] = float32(j) * sX
			verticesY[vCount] = float32(i) * sY
			vertexIndices[vCount] = vCount
			if i == 0 {
				faceMarkers[vCount] = 2 // southBorder
			} else {
				faceMarkers[vCount] = -1
			}
			vCount++

			// right face
			verticesX[vCount] = float32(j+1) * sX
			verticesY[vCount] = float32(i) * sY
			vertexIndices[vCount] = vCount
			if j == sm.NX-1 {
				faceMarkers[vCount] = 1 // eastBorder
			} else {
				faceMarkers[vCount] = -1
			}
			vCount++

			// top face
			verticesX[vCount] = float32(j+1) * sX
			verticesY[vCount] = float32(i+1) * sY
			vertexIndices[vCount] = vCount
			if i == sm.NY-1 {
				faceMarkers[vCount] = 0 // northBorder
			} else {
				faceMarkers[vCount] = -1
			}
			vCount++

			// left face
			verticesX[vCount] = float32(j) * sX
			verticesY[vCount] = float32(i+1) * sY
			vertexIndices[vCount] = vCount
			if j == 0 {
				faceMarkers[vCount] = 3 // westBorder
			} else {
				faceMarkers[vCount] = -1
			}
			vCount++
		}
	}

	faceStarts[nCells] = len(vertexIndices)

	dedupX, dedupY, indexMap := dedupVertices(verticesX, verticesY, 1e-6)
	vertexIndices = remapVertexIndices(vertexIndices, indexMap)
	faceAreas, faceNormalsX, faceNormalsY := calculateFaceGeometry(dedupX, dedupY, vertexIndices, faceStarts)
	cellVolumes, centroidsX, centroidsY := calculateCellGeometry(dedupX, dedupY, vertexIndices, faceStarts)
	neighbourIndices := deriveConnectivity(vertexIndices, faceStarts, faceMarkers)

	// the big one
	connectivityVectorsX,
		connectivityVectorsY,
		connectionDistances,
		faceInterpolationWeights := calculateConnectivityGeometry(
		centroidsX,
		centroidsY,
		neighbourIndices,
		dedupX,
		dedupY,
		vertexIndices,
		faceStarts,
	)

	return &Mesh{
		VerticesX:     dedupX,
		VerticesY:     dedupY,
		VertexIndices: vertexIndices,
		FaceStarts:    faceStarts,
		FaceMarkers:   faceMarkers,

		Bounds:     bounds,
		Boundaries: boundaries,

		FaceAreas:    faceAreas,
		FaceNormalsX: faceNormalsX,
		FaceNormalsY: faceNormalsY,

		CentroidsX:  centroidsX,
		CentroidsY:  centroidsY,
		CellVolumes: cellVolumes,

		NeighbourIndices: neighbourIndices,

		ConnectivityVectorsX:     connectivityVectorsX,
		ConnectivityVectorsY:     connectivityVectorsY,
		ConnectionDistances:      connectionDistances,
		FaceInterpolationWeights: faceInterpolationWeights,
	}
}
