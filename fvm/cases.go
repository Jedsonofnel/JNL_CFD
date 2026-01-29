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

	sys.SolveCG(field, 1e-6, 1000)
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

	sys.SolveBiCGSTAB(phi, 1e-6, 0)

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

	sys.SolveCG(Uy, 1e-6, 1000)

	return Uy, mesh, sys
}

func CaseCouette(nCells int, gamma, Uwall float64) (Ux []float64, mesh *geometry.Mesh, sys *FVSystem) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 1, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()

	mesh, _ = geometry.MeshWithCells(domain, nCells, 30)

	// actual nCells
	nCells = len(mesh.Centroids)
	Ux = make([]float64, nCells)
	// Uy := make([]float64, nCells)

	// For Couette, we only need to solve the x-momentum diffusion equation
	// No pressure coupling needed since dp/dx = 0
	sys = NewFVSystem(mesh)

	// BCs: bottom wall u=0, top wall u=Uwall, sides zero-gradient
	uxBCs := []BC{
		NewDirichlet("south", 0),
		NewDirichlet("north", Uwall),
		NewNeumann("east", 0),
		NewNeumann("west", 0),
	}

	gradUxx := make([]float64, nCells)
	gradUxy := make([]float64, nCells)
	UxFace := make([]float64, len(mesh.Connections))

	// Iterate
	for range 10 {
		sys.Reset()

		FaceInterpCDS(mesh, Ux, UxFace)
		applyBCFaceValues(mesh, Ux, UxFace, uxBCs)
		GreenGaussGradient(mesh, UxFace, gradUxx, gradUxy)

		LaplacianConst(sys, mesh, gamma, gradUxx, gradUxy)
		applyBCs(sys, mesh, uxBCs)

		sys.SolveCG(Ux, 1e-10, 1000)
	}

	return Ux, mesh, sys
}
