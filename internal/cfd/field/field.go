package field

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

type scalar interface {
	GetValues() []float32
	getFaceValues() []float32
}

type scalarDefinition interface {
	Resolve(mesh *geometry.Mesh) (scalar, error)
	follow() scalar
}
