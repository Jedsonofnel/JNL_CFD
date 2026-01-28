package geometry

//
// 1D meshes for testing
//

// MakeSimple1DMesh creates a truly 1D mesh with N cells along [0, 1] Only
// "west" (x=0) and "east" (x=1) boundaries exist
func MakeSimple1DMesh(numCells int) *Mesh {
	if numCells < 1 {
		panic("MakeSimple1DMesh: need at least 1 cell")
	}

	dx := 1.0 / float64(numCells)

	vertices := make([]Vec2, numCells+1)
	for i := 0; i <= numCells; i++ {
		vertices[i] = Vec2{X: float64(i) * dx, Y: 0}
	}

	// Cell geometry is computed directly
	cellVolumes := make([]float64, numCells)
	centroids := make([]Vec2, numCells)
	cellRegions := make([]int, numCells)
	for i := range numCells {
		cellVolumes[i] = dx // "volume" = length in 1D
		centroids[i] = Vec2{X: (float64(i) + 0.5) * dx, Y: 0}
		cellRegions[i] = 1
	}

	// CSR format: 2 vertices per cell (left, right endpoints)
	vertexIndices := make([]int, numCells*2)
	faceStarts := make([]int, numCells+1)
	for i := range numCells {
		faceStarts[i] = i * 2
		vertexIndices[i*2+0] = i
		vertexIndices[i*2+1] = i + 1
	}
	faceStarts[numCells] = numCells * 2

	// Connections: N+1 faces total (N-1 internal + 2 boundary)
	const (
		westMarker = 1
		eastMarker = 2
	)

	numFaces := numCells + 1
	connections := make([]Connection, numFaces)
	faceAreas := make([]float64, numFaces)
	faceNormals := make([]Vec2, numFaces)
	faceCentroids := make([]Vec2, numFaces)
	connectionDists := make([]float64, numFaces)
	interpWeights := make([]float64, numFaces)

	for face := range numFaces {
		faceCentroids[face] = vertices[face]
		faceAreas[face] = 1.0 // "area" of a point = 1 for flux scaling

		switch face {
		case 0: // West boundary
			connections[face] = Connection{Owner: 0, Neighbour: -westMarker}
			faceNormals[face] = Vec2{X: -1, Y: 0}
			connectionDists[face] = 0.5 * dx
			interpWeights[face] = 1.0

		case numCells: // East boundary
			connections[face] = Connection{Owner: int32(numCells - 1), Neighbour: -eastMarker}
			faceNormals[face] = Vec2{X: 1, Y: 0}
			connectionDists[face] = 0.5 * dx
			interpWeights[face] = 1.0

		default: // Internal face between cell (face-1) and cell (face)
			connections[face] = Connection{Owner: int32(face - 1), Neighbour: int32(face)}
			faceNormals[face] = Vec2{X: 1, Y: 0} // points from owner → neighbour
			connectionDists[face] = dx
			interpWeights[face] = 0.5 // symmetric for uniform mesh
		}
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
			westMarker: "west",
			eastMarker: "east",
		},
		RegionNames: map[int]string{1: "default"},
	}

	mesh.buildBoundaryFaces()

	return mesh
}

// MakeRectangular2DStrip creates a simple 1xN rectangular mesh with boundaries
// named "south", "east", "north", "west"
func MakeRectangular2DStrip(numCells int) *Mesh {
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
