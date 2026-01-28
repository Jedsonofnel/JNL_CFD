package fvm

import (
	"jedn.dev/jnlcfd/geometry"
)

func CaseDiffusion1D(nCells int, gamma float64,
) ([]float64, *geometry.Mesh, *FVSystem) {
	mesh := geometry.MakeSimple1DMesh(10)
	field := make([]float64, 10)
	sys := NewFVSystem(mesh)

	LaplacianConst(sys, mesh, gamma, nil, nil)

	DirichletConstBC(sys, mesh, 0, "west")
	DirichletConstBC(sys, mesh, 100, "east")

	sys.Solve(field, 1e-6, 100)
	return field, mesh, sys
}

func CaseConvectionDiffusion1D(
	nCells int,
	gamma, rho, velocity float64,
) ([]float64, *geometry.Mesh, *FVSystem) {
	mesh := geometry.MakeSimple1DMesh(10)
	sys := NewFVSystem(mesh)
	phi := make([]float64, 10)

	Ux := make([]float64, 10)
	for i := range Ux {
		Ux[i] = velocity
	}

	UxFace := make([]float64, len(mesh.Connections))
	UyFace := make([]float64, len(mesh.Connections)) // stays 0

	FaceInterpCDS(mesh, Ux, UxFace)

	Unormal := make([]float64, len(mesh.Connections))

	FaceNormalComponent(mesh, UxFace, UyFace, Unormal)

	LaplacianConst(sys, mesh, gamma, nil, nil)
	DivConstCDS(sys, mesh, rho, Unormal)

	DirichletConstBC(sys, mesh, 0, "west")
	DirichletConstBC(sys, mesh, 100, "east")

	sys.Solve(phi, 1e-6, 100)

	return phi, mesh, sys
}

func CasePoiseuilleGivenPressure(nCells int, gamma, pYgrad float64,
) ([]float64, *geometry.Mesh, *FVSystem) {
	Uy := make([]float64, nCells)
	mesh := geometry.MakeSimple1DMesh(nCells)

	// solve laplacian(Uy) = 1/mu dp/dx
	sys := NewFVSystem(mesh)

	LaplacianConst(sys, mesh, gamma, nil, nil)
	SuConst(sys, mesh, -pYgrad)

	DirichletConstBC(sys, mesh, 0, "west")
	DirichletConstBC(sys, mesh, 0, "east")

	sys.Solve(Uy, 1e-6, 1000)

	return Uy, mesh, sys
}
