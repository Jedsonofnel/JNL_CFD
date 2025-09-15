package geometry

import (
	"math"
)

type MeshDefinition interface {
	Resolve() *Mesh
}

const InternalBoundary = -1

type Mesh struct {
	// Core geometry data
	VerticesX, VerticesY       []float32
	FaceIndices, FaceStarts    []int // polygon faces for rendering
	FaceAreas                  []float32
	FaceNormalsX, FaceNormalsY []float32

	// Cell data
	CentroidsX, CentroidsY []float32
	CellVolumes            []float32

	// Neighbour data
	// parallel to face data - such that a neighbour i has face i -> i+1
	// unless it's the last vertex in which case it's i -> faceStart[cellId]
	CellNeighbours, NeighbourStarts      []int // this is CSR
	NeighbourTypes                       []int // -1=internal, 0+=boundary
	NeighbourDistances                   []float32
	NeighbourNormalsX, NeighbourNormalsY []float32

	// Other details
	Bounds     Rectangle
	Boundaries []string
}

func (m *Mesh) NumCells() int {
	return len(m.CentroidsX)
}

func (m *Mesh) NumNeighbours() int {
	return len(m.CellNeighbours)
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
		for f := m.NeighbourStarts[i]; f < m.NeighbourStarts[i+1]; f++ {
			j := m.CellNeighbours[f]
			if j >= 0 {
				fn(i, j, f)
			}
		}
	}
}

func (m *Mesh) ForEachBoundary(fn func(i, bIdx, face int)) {
	for i := range m.NumCells() {
		for f := m.NeighbourStarts[i]; f < m.NeighbourStarts[i+1]; f++ {
			j := m.CellNeighbours[f]
			if j < 0 {
				bIdx := -j - 1
				fn(i, bIdx, f)
			}
		}
	}
}
