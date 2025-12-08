package geometry

import (
	"strings"

	jnl "jedn.dev/jnlisp"
)

//
// Meshing cell connection
//

// This is the main thing that is looped through in CFD
type Connection struct {
	Owner        int32
	Neighbour    int32   // cell j (or -1 for external boundary)
	Marker       int32   // boundary marker (0 = internal)
	LocalFaceIdx uint8   // 1 byte - which face of Owner (0,1,2 for triangles)
	_            [3]byte // 3 bytes padding
}

//
// Main mesh data structure
//

type Mesh struct {
	// Topology
	Vertices    []Vec2
	Connections []Connection

	// Geometry (parallel to connections)
	FaceAreas       []float64
	FaceNormals     []Vec2
	FaceCentroids   []Vec2
	ConnectionVecs  []Vec2
	ConnectionDists []float64
	InterpWeights   []float64

	// Cell data
	CellRegions []int
	Centroids   []Vec2
	CellVolumes []float64

	// For arbitrary polygon support
	VertexIndices []int
	FaceStarts    []int // CSR format: cell i's faces are at [FaceStarts[i]:FaceStarts[i+1]]

	// Meta
	BoundaryNames map[int]string
	RegionNames   map[int]string
	Domain        *Domain
}

// Mesh Sexp implementation
func (m *Mesh) String() string {
	return jnl.FormatNonReadable("cfd", "mesh")
}

func (m *Mesh) Type() string {
	return "mesh"
}

func (m *Mesh) Keys() []jnl.Hashable {
	return []jnl.Hashable{
		jnl.NewKeyword("vertices"),
		jnl.NewKeyword("vertex-indices"),
		jnl.NewKeyword("face-starts"),
		jnl.NewKeyword("domain"),
	}
}

func (m *Mesh) Lookup(key jnl.Hashable) jnl.Sexp {
	name := strings.TrimLeft(key.String(), ":")
	switch name {
	case "vertices":
		return NewVectorTuple(m.Vertices)
	case "vertex-indices":
		return jnl.NewIntTuple(m.VertexIndices)
	case "face-starts":
		return jnl.NewIntTuple(m.FaceStarts)
	case "domain":
		return jnl.ToMap(m.Domain)
	default:
		return jnl.Nil{}
	}
}

// Get the polygon vertices associated with a connection
func (m *Mesh) GetConnectionVertices(connIdx int) (v0, v1 Vec2) {
	conn := m.Connections[connIdx]
	owner := int(conn.Owner)
	localIdx := int(conn.LocalFaceIdx)

	startIdx := m.FaceStarts[owner]
	endIdx := m.FaceStarts[owner+1]

	faceIdx := startIdx + localIdx
	nextFaceIdx := startIdx + (localIdx+1)%(endIdx-startIdx)

	vi0 := m.VertexIndices[faceIdx]
	vi1 := m.VertexIndices[nextFaceIdx]

	return m.Vertices[vi0], m.Vertices[vi1]
}

//
// Rendering implementation
//

func TriangulateMesh(mesh *Mesh) (vertices []float64, triToCells []int) {
	// Count triangles first for allocation
	numTris := 0
	for i := 0; i < len(mesh.FaceStarts)-1; i++ {
		nVerts := mesh.FaceStarts[i+1] - mesh.FaceStarts[i]
		numTris += max(0, nVerts-2) // fan triangulation
	}

	vertices = make([]float64, numTris*6)
	triToCells = make([]int, numTris)

	triIdx := 0
	for cellIdx := 0; cellIdx < len(mesh.FaceStarts)-1; cellIdx++ {
		start := mesh.FaceStarts[cellIdx]
		end := mesh.FaceStarts[cellIdx+1]
		nVerts := end - start

		// Fan triangulation from vertex 0
		v0 := mesh.Vertices[mesh.VertexIndices[start]]
		for i := 1; i < nVerts-1; i++ {
			v1 := mesh.Vertices[mesh.VertexIndices[start+i]]
			v2 := mesh.Vertices[mesh.VertexIndices[start+i+1]]

			baseIdx := triIdx * 6
			vertices[baseIdx+0] = v0.X
			vertices[baseIdx+1] = v0.Y
			vertices[baseIdx+2] = v1.X
			vertices[baseIdx+3] = v1.Y
			vertices[baseIdx+4] = v2.X
			vertices[baseIdx+5] = v2.Y

			triToCells[triIdx] = cellIdx
			triIdx++
		}
	}

	return vertices, triToCells
}
