package geometry

//
// 1D meshes for testing
//

// MakeRectangular1DMesh creates a simple 1xN rectangular mesh
// with boundaries named "south", "east", "north", "west"
func MakeRectangular1DMesh(numCells int) *Mesh {
	if numCells < 1 {
		panic("MakeRectangular1DMesh: need at least 1 cell")
	}

	dx := 1.0 / float64(numCells)

	// Vertices: bottom row then top row
	numVerts := 2 * (numCells + 1)
	vertices := make([]Vec2, numVerts)
	for i := 0; i <= numCells; i++ {
		vertices[i] = Vec2{X: float64(i) * dx, Y: 0}
		vertices[numCells+1+i] = Vec2{X: float64(i) * dx, Y: 1}
	}

	// CSR format: 4 vertices per cell, CCW order
	vertexIndices := make([]int, numCells*4)
	faceStarts := make([]int, numCells+1)
	faceMarkers := make([]int, numCells*4)

	const (
		southMarker = 1
		eastMarker  = 2
		northMarker = 3
		westMarker  = 4
	)

	for i := range numCells {
		base := i * 4
		faceStarts[i] = base

		// CCW: bottom-left → bottom-right → top-right → top-left
		vertexIndices[base+0] = i                    // BL
		vertexIndices[base+1] = i + 1                // BR
		vertexIndices[base+2] = numCells + 1 + i + 1 // TR
		vertexIndices[base+3] = numCells + 1 + i     // TL

		// Face markers: [south, east, north, west]
		faceMarkers[base+0] = southMarker                                     // south edge (always boundary)
		faceMarkers[base+1] = map[bool]int{true: eastMarker}[i == numCells-1] // east edge (only last cell)
		faceMarkers[base+2] = northMarker                                     // north edge (always boundary)
		faceMarkers[base+3] = map[bool]int{true: westMarker}[i == 0]          // west edge (only first cell)
	}
	faceStarts[numCells] = numCells * 4

	// Reuse existing infrastructure
	cellVolumes, centroids := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	connections, faceAreas, faceNormals, faceCentroids, connectionDists, interpWeights :=
		buildConnectionGeometry(vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	cellRegions := make([]int, numCells)
	for i := range cellRegions {
		cellRegions[i] = 1
	}

	mesh := &Mesh{
		Vertices:        vertices,
		Connections:     connections,
		FaceAreas:       faceAreas,
		FaceNormals:     faceNormals,
		FaceCentroids:   faceCentroids,
		ConnectionDists: connectionDists,
		InterpWeights:   interpWeights,
		CellRegions:     cellRegions,
		Centroids:       centroids,
		CellVolumes:     cellVolumes,
		VertexIndices:   vertexIndices,
		FaceStarts:      faceStarts,
		BoundaryNames: map[int]string{
			southMarker: "south",
			eastMarker:  "east",
			northMarker: "north",
			westMarker:  "west",
		},
		RegionNames: map[int]string{1: "default"},
	}

	mesh.buildBoundaryFaces()

	return mesh
}
