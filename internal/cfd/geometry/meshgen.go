package geometry

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry/triangle"
)

type PSLG struct {
	Points   []Vec2
	Segments []Segment
	Holes    []Vec2
	Regions  []Region
}

//
// Converts to C types and calls CGO wrapper triangle package
//

func MeshDomain(domain *Domain) (*Mesh, error) {
	_, _ = triangle.Triangulate(triangle.Input{}, "some-options")
	return nil, nil
}
