//go:build !wasm

package nativedisp

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

// Triangle represents a simple triangle for rendering
type Triangle struct {
	V0, V1, V2 geometry.Vec2
}

// FanTriangulate creates triangles from a polygon using fan triangulation
// Picks first vertex and connects to all non-adjacent vertices
// Works well for convex polygons, may fail for non-convex
func FanTriangulate(vertices []geometry.Vec2) []Triangle {
	if len(vertices) < 3 {
		return nil
	}

	triangles := make([]Triangle, 0, len(vertices)-2)

	// Fan from first vertex
	v0 := vertices[0]
	for i := 1; i < len(vertices)-1; i++ {
		triangles = append(triangles, Triangle{
			V0: v0,
			V1: vertices[i],
			V2: vertices[i+1],
		})
	}

	return triangles
}

// CentroidTriangulate creates triangles from a polygon using centroid
// Creates triangle from centroid to each edge
// Works for any polygon (convex or non-convex)
func CentroidTriangulate(vertices []geometry.Vec2, centroid geometry.Vec2) []Triangle {
	if len(vertices) < 3 {
		return nil
	}

	triangles := make([]Triangle, len(vertices))

	for i := 0; i < len(vertices); i++ {
		v0 := vertices[i]
		v1 := vertices[(i+1)%len(vertices)]

		triangles[i] = Triangle{
			V0: centroid,
			V1: v0,
			V2: v1,
		}
	}

	return triangles
}

// GetCellVertices extracts vertices for a given cell
func GetCellVertices(mesh *geometry.Mesh, cellID int) []geometry.Vec2 {
	startIdx := mesh.FaceStarts[cellID]
	endIdx := mesh.FaceStarts[cellID+1]

	vertices := make([]geometry.Vec2, endIdx-startIdx)
	for i := startIdx; i < endIdx; i++ {
		vi := mesh.VertexIndices[i]
		vertices[i-startIdx] = mesh.Vertices[vi]
	}

	return vertices
}
