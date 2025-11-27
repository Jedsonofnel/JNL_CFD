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

