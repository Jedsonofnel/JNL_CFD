package geometry

import (
	"fmt"
	"github.com/Jedsonofnel/cfd-but-wasm/linalg"
)

const (
	westBorder = iota
	southBorder
	eastBorder
	northBorder
)

type StructuredMeshFactory struct {
	nX, nY  int
	spacing linalg.Vec2
	bounds  Rectangle
}

func NewStructuredMeshFactory(nX, nY int, width, height float32) *StructuredMeshFactory {
	spacing := linalg.Vec2{X: width / float32(nX), Y: height / float32(nY)}
	bounds := Rectangle{Height: height, Width: width}

	return &StructuredMeshFactory{
		nX:      nX,
		nY:      nY,
		spacing: spacing,
		bounds:  bounds,
	}
}

func NewStructuredMesh(nX, nY int, width, height float32) *Mesh {
	smf := NewStructuredMeshFactory(nX, nY, width, height)

	mesh := smf.initializeMesh()
	smf.populateCells(mesh)
	smf.populateFaceGeometry(mesh)

	return mesh
}

func (smf *StructuredMeshFactory) initializeMesh() *Mesh {
	numCells := smf.nX * smf.nY
	numVertices := (smf.nX + 1) * (smf.nY + 1)
	numNeighbours := numCells * 4

	return &Mesh{
		VerticesX:    make([]float32, numVertices),
		VerticesY:    make([]float32, numVertices),
		FaceIndices:  make([]int, 4*numCells),
		FaceStarts:   make([]int, numCells+1),
		FaceAreas:    make([]float32, numNeighbours),
		FaceNormalsX: make([]float32, numNeighbours),
		FaceNormalsY: make([]float32, numNeighbours),

		CentroidsX:  make([]float32, numCells),
		CentroidsY:  make([]float32, numCells),
		CellVolumes: make([]float32, numCells),

		CellNeighbours:     make([]int, numNeighbours),
		NeighbourStarts:    make([]int, numCells+1),
		NeighbourTypes:     make([]int, numNeighbours),
		NeighbourDistances: make([]float32, numNeighbours),
		NeighbourNormalsX:  make([]float32, numNeighbours),
		NeighbourNormalsY:  make([]float32, numNeighbours),

		Bounds:     smf.bounds,
		Boundaries: []string{"west", "south", "east", "north"},
	}
}

func (smf *StructuredMeshFactory) populateCells(mesh *Mesh) {
	vertexMap := make(map[string]int)
	nextVertexIndex := 0
	faceIdx := 0 // this doubles as neighbour index
	numCells := len(mesh.CentroidsX)

	for i := range numCells {
		row := i / smf.nX
		col := i % smf.nX

		cX := (float32(col) + 0.5) * smf.spacing.X
		cY := (float32(row) + 0.5) * smf.spacing.Y

		mesh.CentroidsX[i] = cX
		mesh.CentroidsY[i] = cY
		mesh.CellVolumes[i] = smf.spacing.X * smf.spacing.Y

		vertices := polygonVertices(cX, cY, smf.spacing)
		neighbours := smf.cellNeighbours(row, col, i)

		mesh.FaceStarts[i] = faceIdx
		mesh.NeighbourStarts[i] = faceIdx

		for face, vertex := range vertices { // west, south, east, north
			key := fmt.Sprintf("%.6f,%.6f", vertex.X, vertex.Y)

			if existingIndex, found := vertexMap[key]; found {
				mesh.FaceIndices[faceIdx] = existingIndex
			} else {
				mesh.VerticesX[nextVertexIndex] = vertex.X
				mesh.VerticesY[nextVertexIndex] = vertex.Y
				vertexMap[key] = nextVertexIndex
				mesh.FaceIndices[faceIdx] = nextVertexIndex
				nextVertexIndex++
			}

			mesh.CellNeighbours[faceIdx] = neighbours[face].neighbourIndex
			mesh.NeighbourTypes[faceIdx] = neighbours[face].neighbourType
			mesh.NeighbourDistances[faceIdx] = neighbours[face].distance
			mesh.NeighbourNormalsX[faceIdx] = neighbours[face].neighbourNormalX
			mesh.NeighbourNormalsY[faceIdx] = neighbours[face].neighbourNormalY

			faceIdx++
		}
	}

	// CSR terminators
	mesh.FaceStarts[numCells] = faceIdx
	mesh.NeighbourStarts[numCells] = faceIdx
}

func polygonVertices(cX, cY float32, spacing linalg.Vec2) []linalg.Vec2 {
	return []linalg.Vec2{ // starts top left and goes CCW
		{X: cX - spacing.X/2, Y: cY + spacing.Y/2},
		{X: cX - spacing.X/2, Y: cY - spacing.Y/2},
		{X: cX + spacing.X/2, Y: cY - spacing.Y/2},
		{X: cX + spacing.X/2, Y: cY + spacing.Y/2},
	}
}

type CellNeighbour struct {
	neighbourIndex   int
	neighbourType    int
	distance         float32
	neighbourNormalX float32
	neighbourNormalY float32
}

func (smf *StructuredMeshFactory) cellNeighbours(row, col, cellIndex int) [4]CellNeighbour {
	// (0, 0) = bottom left
	neighbours := [4]CellNeighbour{ // west south east north
		{cellIndex - 1, -1, smf.spacing.X, -1, 0},
		{cellIndex - smf.nX, -1, smf.spacing.Y, 0, -1},
		{cellIndex + 1, -1, smf.spacing.X, 1, 0},
		{cellIndex + smf.nX, -1, smf.spacing.Y, 0, 1},
	}

	if col == 0 { // west border
		neighbours[0].neighbourIndex = -1
		neighbours[0].neighbourType = westBorder
		neighbours[0].distance = smf.spacing.X / 2
		neighbours[0].neighbourNormalX = -1
		neighbours[0].neighbourNormalY = 0
	}
	if row == 0 { // south
		neighbours[1].neighbourIndex = -1
		neighbours[1].neighbourType = southBorder
		neighbours[1].distance = smf.spacing.Y / 2
		neighbours[0].neighbourNormalX = 0
		neighbours[0].neighbourNormalY = -1
	}
	if col == smf.nX-1 { // east
		neighbours[2].neighbourIndex = -1
		neighbours[2].neighbourType = eastBorder
		neighbours[2].distance = smf.spacing.X / 2
		neighbours[0].neighbourNormalX = 1
		neighbours[0].neighbourNormalY = 0
	}
	if row == smf.nY-1 { // north
		neighbours[3].neighbourIndex = -1
		neighbours[3].neighbourType = northBorder
		neighbours[3].distance = smf.spacing.Y / 2
		neighbours[0].neighbourNormalX = 0
		neighbours[0].neighbourNormalY = 1
	}

	return neighbours
}

func (smf *StructuredMeshFactory) populateFaceGeometry(mesh *Mesh) {
	numCells := len(mesh.CentroidsX)

	for cellIdx := range numCells {
		facesStart := mesh.FaceStarts[cellIdx]
		facesEnd := mesh.FaceStarts[cellIdx+1]

		for i := range facesEnd - facesStart {
			startIdx := facesStart + i
			endIdx := startIdx + 1
			if endIdx == facesEnd {
				endIdx = facesStart
			}

			startVertexIdx := mesh.FaceIndices[startIdx]
			startX, startY := mesh.VerticesX[startVertexIdx], mesh.VerticesY[startVertexIdx]

			endVertexIdx := mesh.FaceIndices[endIdx]
			endX, endY := mesh.VerticesX[endVertexIdx], mesh.VerticesY[endVertexIdx]

			edge := linalg.Vec2{X: endX - startX, Y: endY - startY}
			mesh.FaceAreas[startIdx] = edge.Magnitude()

			normal := edge.UnitCCWNormal()
			mesh.FaceNormalsX[startIdx] = normal.X
			mesh.FaceNormalsY[startIdx] = normal.Y
		}
	}
}
