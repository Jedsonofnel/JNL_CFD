package cfd

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

func SampleStructuredMesh() geometry.MeshDefinition {
	return geometry.NewStructuredMesh(40, 20, 1, 0.5)
}
