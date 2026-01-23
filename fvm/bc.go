package fvm

import (
	"jedn.dev/jnlcfd/geometry"
)

//
// Boundary conditions - act like source terms
//

func DirichletConstBC(
	system *FVSystem,
	mesh *geometry.Mesh,
	value float64,
	boundaryName string,
) {
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)
	matrix := system.Matrix
	for i, conn := range matrix.conns {
		if conn.Neighbour == boundaryMarker {
			bcCoeff := -matrix.upper[i]
			diagCoeff := -matrix.lower[i]
			matrix.diag[conn.Owner] += diagCoeff
			system.Rhs[conn.Owner] += value * bcCoeff
		}
	}
}
func NeumannConstBC(
	system *FVSystem,
	mesh *geometry.Mesh,
	flux float64,
	boundaryName string,
) {
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)

	for i, conn := range system.Matrix.conns {
		if conn.Neighbour == boundaryMarker {
			system.Rhs[conn.Owner] += flux * mesh.FaceAreas[i]
		}
	}
}

//
// Helpers
//

func findBoundaryMarker(mesh *geometry.Mesh, name string) int32 {
	for marker, boundaryName := range mesh.BoundaryNames {
		if boundaryName == name {
			return -int32(marker)
		}
	}

	// TODO wrap in an error
	panic("boundary " + name + " not found")
}
