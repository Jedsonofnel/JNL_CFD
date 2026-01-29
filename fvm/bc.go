package fvm

import (
	"jedn.dev/jnlcfd/geometry"
)

type BCType int

const (
	Dirichlet BCType = iota
	Neumann
)

// BC is a spec for a constant-value BC (dirichlet or Neumann)
type BC struct {
	Boundary string
	Type     BCType
	Value    float64
}

func NewDirichlet(name string, value float64) BC {
	return BC{
		Boundary: name,
		Type:     Dirichlet,
		Value:    value,
	}
}

func NewNeumann(name string, flux float64) BC {
	return BC{
		Boundary: name,
		Type:     Neumann,
		Value:    flux,
	}
}

//
// Boundary conditions - act like source terms
//

func DirichletConstBC(
	sys *FVSystem,
	mesh *geometry.Mesh,
	value float64,
	boundaryName string,
) {
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)
	matrix := sys.Matrix
	// hasGrads := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range matrix.conns {
		if conn.Neighbour == boundaryMarker {
			bcCoeff := -matrix.upper[i]
			diagCoeff := -matrix.lower[i]
			matrix.diag[conn.Owner] += diagCoeff
			sys.Rhs[conn.Owner] += value * bcCoeff
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
// BC Application
//

func applyBCs(sys *FVSystem, mesh *geometry.Mesh, bcs []BC) {
	for _, bc := range bcs {
		switch bc.Type {
		case Dirichlet:
			DirichletConstBC(sys, mesh, bc.Value, bc.Boundary)
		case Neumann:
			NeumannConstBC(sys, mesh, bc.Value, bc.Boundary)
		}
	}
}

func applyBCFaceValues(mesh *geometry.Mesh, field, faceValues []float64, bcs []BC) {
	for _, bc := range bcs {
		switch bc.Type {
		case Dirichlet:
			DirichletFaceValuesConst(mesh, faceValues, bc.Boundary, bc.Value)
		case Neumann:
			NeumannFaceValuesConst(mesh, field, faceValues, bc.Boundary, bc.Value)
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
