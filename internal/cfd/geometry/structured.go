package geometry

import (
	"fmt"
)

const (
	westBorder = iota
	southBorder
	eastBorder
	northBorder
)

type structuredMesh struct {
	NX     int     `json:"nx"`
	NY     int     `json:"ny"`
	Width  float32 `json:"width"`
	Height float32 `json:"height"`
}

func NewStructuredMesh(nX, nY int, width, height float64) MeshDefinition {
	return &structuredMesh{nX, nY, float32(width), float32(height)}
}

func (sm *structuredMesh) spacing() (sX, sY float32) {
	sX = sm.Width / float32(sm.NX)
	sY = sm.Height / float32(sm.NY)
	return
}

func (sm *structuredMesh) numCells() int {
	return sm.NX * sm.NY
}

func (sm *structuredMesh) Resolve() *Mesh {
	mesh := initializeMesh(sm)
	populateCells(mesh, sm)
	populateFaceGeometry(mesh, sm)

	return mesh
}

func initializeMesh(sm *structuredMesh) *Mesh {
	numCells := sm.numCells()
	numVertices := (sm.NX + 1) * (sm.NY + 1)
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

		Bounds:     Rectangle{Height: sm.Height, Width: sm.Width},
		Boundaries: []string{"west", "south", "east", "north"},
	}
}

func populateCells(mesh *Mesh, sm *structuredMesh) {
	sX, sY := sm.spacing()
	vertexMap := make(map[string]int)
	nextVertexIndex := 0
	faceIdx := 0 // this doubles as neighbour index
	numCells := len(mesh.CentroidsX)

	for i := range numCells {
		row := i / sm.NX
		col := i % sm.NX

		cX := (float32(col) + 0.5) * sX
		cY := (float32(row) + 0.5) * sY

		mesh.CentroidsX[i] = cX
		mesh.CentroidsY[i] = cY
		mesh.CellVolumes[i] = sX * sY

		polygonX, polygonY := polygonVertices(cX, cY, sX, sY)
		neighbours := cellNeighbours(sm, row, col, i)

		mesh.FaceStarts[i] = faceIdx
		mesh.NeighbourStarts[i] = faceIdx

		for face := range polygonX { // west, south, east, north
			key := fmt.Sprintf("%.6f,%.6f", polygonX[face], polygonY[face])

			if existingIndex, found := vertexMap[key]; found {
				mesh.FaceIndices[faceIdx] = existingIndex
			} else {
				mesh.VerticesX[nextVertexIndex] = polygonX[face]
				mesh.VerticesY[nextVertexIndex] = polygonY[face]
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

func polygonVertices(cX, cY, sX, sY float32) ([]float32, []float32) {
	// top left and goes CCS
	polygonX := []float32{cX - sX/2, cX - sX/2, cX + sX/2, cX + sX/2}
	polygonY := []float32{cY + sY/2, cY - sY/2, cY - sY/2, cY + sY/2}
	return polygonX, polygonY
}

type CellNeighbour struct {
	neighbourIndex   int
	neighbourType    int
	distance         float32
	neighbourNormalX float32
	neighbourNormalY float32
}

func cellNeighbours(sm *structuredMesh, row, col, cellIndex int) [4]CellNeighbour {
	sX, sY := sm.spacing()

	// (0, 0) = bottom left
	neighbours := [4]CellNeighbour{ // west south east north
		{cellIndex - 1, -1, sX, -1, 0},
		{cellIndex - sm.NX, -1, sY, 0, -1},
		{cellIndex + 1, -1, sX, 1, 0},
		{cellIndex + sm.NX, -1, sY, 0, 1},
	}

	if col == 0 { // west border
		neighbours[0].neighbourIndex = -1
		neighbours[0].neighbourType = westBorder
		neighbours[0].distance = sX / 2
		neighbours[0].neighbourNormalX = -1
		neighbours[0].neighbourNormalY = 0
	}
	if row == 0 { // south
		neighbours[1].neighbourIndex = -1
		neighbours[1].neighbourType = southBorder
		neighbours[1].distance = sY / 2
		neighbours[0].neighbourNormalX = 0
		neighbours[0].neighbourNormalY = -1
	}
	if col == sm.NX-1 { // east
		neighbours[2].neighbourIndex = -1
		neighbours[2].neighbourType = eastBorder
		neighbours[2].distance = sX / 2
		neighbours[0].neighbourNormalX = 1
		neighbours[0].neighbourNormalY = 0
	}
	if row == sm.NY-1 { // north
		neighbours[3].neighbourIndex = -1
		neighbours[3].neighbourType = northBorder
		neighbours[3].distance = sY / 2
		neighbours[0].neighbourNormalX = 0
		neighbours[0].neighbourNormalY = 1
	}

	return neighbours
}

func populateFaceGeometry(mesh *Mesh, sm *structuredMesh) {
	numCells := sm.numCells()

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

			edge := Vec2{X: endX - startX, Y: endY - startY}
			mesh.FaceAreas[startIdx] = edge.Magnitude()

			normal := edge.UnitCCWNormal()
			mesh.FaceNormalsX[startIdx] = normal.X
			mesh.FaceNormalsY[startIdx] = normal.Y
		}
	}
}
