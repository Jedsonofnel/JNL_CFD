package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

func main() {
	sm := geometry.NewStructuredMesh(200, 100, 0.5, 0.25)
	mesh := sm.Resolve()
}
