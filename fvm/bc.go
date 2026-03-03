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
			// Absorb pending operator coefficients: for zero-gradient,
			// φ_face = φ_owner so the face-value term becomes implicit.
			// Same decomposition as Dirichlet but both parts go to diagonal.
			system.Matrix.diag[conn.Owner] +=
				system.Matrix.upper[i] - system.Matrix.lower[i]

			system.Rhs[conn.Owner] += flux * mesh.FaceAreas[i]
		}
	}
}

//
// Face interpolation at BCs
//

func DirichletFaceValuesConst(mesh *geometry.Mesh, faceField []float64, boundaryName string, value float64) {
	faceIndices := mesh.BoundaryFaces[boundaryName]
	for _, connIdx := range faceIndices {
		faceField[connIdx] = value
	}
}

func NeumannFaceValuesConst(mesh *geometry.Mesh, field, faceField []float64, boundaryName string, flux float64) {
	faceIndices := mesh.BoundaryFaces[boundaryName]
	for _, connIdx := range faceIndices {
		owner := mesh.Connections[connIdx].Owner
		dist := mesh.ConnectionDists[connIdx]
		faceField[connIdx] = field[owner] + flux*dist
	}
}

//
// Face-normal velocity BCs for Rhie-Chow boundary faces
//

// DirichletFaceNormalConst sets the face-normal velocity on boundary faces
// from known velocity component values: Un = uxValue*nx + uyValue*ny
func DirichletFaceNormalConst(
	mesh *geometry.Mesh,
	UnFace []float64,
	boundaryName string,
	uxValue, uyValue float64,
) {
	for _, fi := range mesh.BoundaryFaces[boundaryName] {
		n := mesh.FaceNormals[fi]
		UnFace[fi] = uxValue*n.X + uyValue*n.Y
	}
}

// NeumannFaceNormalConst sets the face-normal velocity on boundary faces
// by extrapolating from cell-centre values (zero-gradient when flux=0):
// Un = (Ux[owner] + uxFlux*dist)*nx + (Uy[owner] + uyFlux*dist)*ny
func NeumannFaceNormalConst(
	mesh *geometry.Mesh,
	Ux, Uy []float64,
	UnFace []float64,
	boundaryName string,
	uxFlux, uyFlux float64,
) {
	for _, fi := range mesh.BoundaryFaces[boundaryName] {
		owner := mesh.Connections[fi].Owner
		dist := mesh.ConnectionDists[fi]
		n := mesh.FaceNormals[fi]
		UnFace[fi] = (Ux[owner]+uxFlux*dist)*n.X + (Uy[owner]+uyFlux*dist)*n.Y
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

// applyBCFaceNormals fills boundary entries in UnFace using paired
// uxBCs/uyBCs. Dirichlet velocity boundaries get the known value; Neumann
// velocity boundaries get cell-centre extrapolation. uxBCs and uyBCs must list
// boundaries in the same order.
func applyBCFaceNormals(
	mesh *geometry.Mesh,
	Ux, Uy []float64,
	UnFace []float64,
	uxBCs, uyBCs []BC,
) {
	for i, uxBC := range uxBCs {
		uyBC := uyBCs[i]
		switch uxBC.Type {
		case Dirichlet:
			DirichletFaceNormalConst(mesh, UnFace, uxBC.Boundary, uxBC.Value, uyBC.Value)
		case Neumann:
			NeumannFaceNormalConst(mesh, Ux, Uy, UnFace, uxBC.Boundary, uxBC.Value, uyBC.Value)
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
