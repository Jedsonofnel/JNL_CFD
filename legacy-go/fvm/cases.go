package fvm

import (
	"math"

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

func CasePoiseuille(nCells int, gamma, pXgrad float64) ([]float64, *geometry.Mesh, *FVSystem) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 1, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, nCells, 30)

	nCells = len(mesh.Centroids)
	Ux := make([]float64, nCells)
	sys := NewFVSystem(mesh)

	uxBCs := []BC{
		NewDirichlet("south", 0),
		NewDirichlet("north", 0),
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
		SuConst(sys, mesh, -pXgrad)
		applyBCs(sys, mesh, uxBCs)

		sys.SolveCG(Ux, 1e-10, 1000)
	}

	return Ux, mesh, sys
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

//
// SIMPLE-based cases (full pressure-velocity coupling with convection)
//

type SIMPLEResult struct {
	Mesh       *geometry.Mesh
	P, Ux, Uy  []float64
	Iterations int
	FinalRes   float64
}

func CasePoiseuilleSIMPLE(nCells int, gamma, rho float64) SIMPLEResult {
	// 4:1 aspect ratio channel
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, nCells, 30)

	// Pressure-driven channel: Dirichlet p at inlet/outlet, no-slip walls
	pBCs := []BC{
		NewDirichlet("west", 1.0),
		NewDirichlet("east", 0.0),
		NewNeumann("north", 0),
		NewNeumann("south", 0),
	}
	// Fully developed: zero-gradient velocity at inlet/outlet, no-slip walls
	uxBCs := []BC{
		NewNeumann("west", 0),
		NewNeumann("east", 0),
		NewDirichlet("north", 0),
		NewDirichlet("south", 0),
	}
	uyBCs := []BC{
		NewDirichlet("west", 0),
		NewDirichlet("east", 0),
		NewDirichlet("north", 0),
		NewDirichlet("south", 0),
	}

	solver, p, Ux, Uy := MakeSIMPLE(mesh, gamma, rho, 0.7, 0.3, pBCs, uxBCs, uyBCs, nil)

	var finalRes float64
	iters := 0
	for i := range 1000 {
		res := solver()
		iters = i + 1
		finalRes = res
		if res < 1e-6 {
			break
		}
	}

	return SIMPLEResult{
		Mesh: mesh, P: p, Ux: Ux, Uy: Uy,
		Iterations: iters, FinalRes: finalRes,
	}
}

func CaseLidDrivenCavity(nCells int, Re float64) SIMPLEResult {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 1, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, nCells, 30)

	// Re = rho * Ulid * L / gamma, fix rho=1, Ulid=1, L=1 => gamma = 1/Re
	Ulid := 1.0
	rho := 1.0
	gamma := 1.0 / Re

	pBCs := []BC{
		NewNeumann("north", 0), NewNeumann("south", 0),
		NewNeumann("east", 0), NewNeumann("west", 0),
	}
	uxBCs := []BC{
		NewDirichlet("north", Ulid),
		NewDirichlet("south", 0),
		NewDirichlet("east", 0),
		NewDirichlet("west", 0),
	}
	uyBCs := []BC{
		NewDirichlet("north", 0),
		NewDirichlet("south", 0),
		NewDirichlet("east", 0),
		NewDirichlet("west", 0),
	}

	alphaU := 0.7
	alphaP := 0.3
	maxIters := 2000
	if Re > 400 {
		alphaU = 0.5
		alphaP = 0.2
		maxIters = 5000
	}
	if Re > 1000 {
		alphaU = 0.3
		alphaP = 0.1
		maxIters = 10000
	}

	solver, p, Ux, Uy := MakeSIMPLE(mesh, gamma, rho, alphaU, alphaP, pBCs, uxBCs, uyBCs, nil)

	var finalRes float64
	iters := 0
	for i := range maxIters {
		res := solver()
		iters = i + 1
		finalRes = res
		if res < 1e-6 {
			break
		}
	}

	return SIMPLEResult{
		Mesh: mesh, P: p, Ux: Ux, Uy: Uy,
		Iterations: iters, FinalRes: finalRes,
	}
}

//
// Developing Poiseuille Flow
//

func CaseDevelopingPoiseuille(nCells int, Re float64) SIMPLEResult {
	// Nondimensionalize by setting rho and Uin to 1.0
	// and deriving gamma from the Reynolds number and channel height (H).
	rho := 1.0
	Uin := 1.0
	H := 1.0
	gamma := (rho * Uin * H) / Re

	// L = 20, H = 1 to allow the parabolic profile to fully develop
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 20, H, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, nCells, 30)

	// Uniform velocity inlet, zero pressure gradient
	// Fixed pressure outlet, zero velocity gradient
	pBCs := []BC{
		NewNeumann("west", 0.0),
		NewDirichlet("east", 0.0),
		NewNeumann("north", 0.0),
		NewNeumann("south", 0.0),
	}
	uxBCs := []BC{
		NewDirichlet("west", Uin),
		NewNeumann("east", 0.0),
		NewDirichlet("north", 0.0),
		NewDirichlet("south", 0.0),
	}
	uyBCs := []BC{
		NewDirichlet("west", 0.0),
		NewNeumann("east", 0.0),
		NewDirichlet("north", 0.0),
		NewDirichlet("south", 0.0),
	}

	solver, p, Ux, Uy := MakeSIMPLE(mesh, gamma, rho, 0.7, 0.3, pBCs, uxBCs, uyBCs, nil)

	var finalRes float64
	iters := 0
	for i := range 2000 { // Might need more iterations for a long domain
		res := solver()
		iters = i + 1
		finalRes = res
		if res < 1e-6 {
			break
		}
	}

	return SIMPLEResult{
		Mesh:       mesh,
		P:          p,
		Ux:         Ux,
		Uy:         Uy,
		Iterations: iters,
		FinalRes:   finalRes,
	}
}

//
// Thermal
//

type ThermalResult struct {
	Mesh         *geometry.Mesh
	P, Ux, Uy, T []float64
	Iterations   int
}

// CaseForcedConvectionPlate solves fluid flow over a flat plate,
// then solves the decoupled temperature field with a heated bottom wall.
func CaseForcedConvectionPlate(nCells int, Uin, heatFlux float64) ThermalResult {
	// L = 10, H = 2
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 10, 2, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, nCells, 30)

	rho := 1.0
	nu := 0.01 // Kinematic viscosity
	gamma := rho * nu

	// 1. Hydrodynamic BCs (Flow over a flat plate)
	pBCs := []BC{
		NewNeumann("west", 0), NewDirichlet("east", 0),
		NewNeumann("north", 0), NewNeumann("south", 0),
	}
	uxBCs := []BC{
		NewDirichlet("west", Uin), NewNeumann("east", 0),
		NewNeumann("north", 0),   // Slip wall on top boundary
		NewDirichlet("south", 0), // No-slip flat plate
	}
	uyBCs := []BC{
		NewDirichlet("west", 0), NewNeumann("east", 0),
		NewDirichlet("north", 0), // Slip wall on top boundary
		NewDirichlet("south", 0), // No-slip flat plate
	}

	// 2. Solve hydrodynamics using SIMPLE
	solver, p, Ux, Uy := MakeSIMPLE(mesh, gamma, rho, 0.7, 0.3, pBCs, uxBCs, uyBCs, nil)

	iters := 0
	for i := range 2000 {
		res := solver()
		iters = i + 1
		if res < 1e-6 {
			break
		}
	}

	// 3. Thermal BCs
	TBCs := []BC{
		NewDirichlet("west", 300.0),   // Fixed inlet temp
		NewNeumann("east", 0.0),       // Zero gradient outlet
		NewNeumann("north", 0.0),      // Insulated top wall
		NewNeumann("south", heatFlux), // Constant heat flux from the bottom plate
	}

	rhoCp := 1000.0
	k := 0.026
	Tref := 300.0

	// 4. Solve Decoupled Temperature
	T := SolveTemperature(mesh, Ux, Uy, uxBCs, uyBCs, TBCs, rhoCp, k, Tref)

	return ThermalResult{
		Mesh: mesh, P: p, Ux: Ux, Uy: Uy, T: T,
		Iterations: iters,
	}
}

//
// Conjugate Heat Transfer (Heated Block in Channel)
//

type CHTResult struct {
	Mesh         *geometry.Mesh
	P, Ux, Uy, T []float64
	Iterations   int
	FinalRes     float64
}

func CaseHeatedBlockCHT(nCells int, Uin float64) CHTResult {
	db := geometry.DomainBuilder{}
	// Main fluid channel [10 x 2]
	db.AddPolygon(geometry.MakeRectangle(0, 0, 10, 2, "fluid", "south", "east", "north", "west"))
	// Solid block sitting on the bottom wall [1 x 0.5]
	db.AddPolygon(geometry.MakeRectangle(3, 0, 1, 0.5, "solid", "solid_south", "solid_east", "solid_north", "solid_west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, nCells, 30)

	cfg := CHTConfig{
		FluidRegions: []string{"fluid"},
		SolidRegions: []string{"solid"},
		UseBuoyancy:  false, // Pure forced convection
		RhoFluid:     1.0,
		NuFluid:      0.01,
		Tref:         300.0,
		AlphaU:       0.7,
		AlphaP:       0.3,
		AlphaT:       0.9,
		RhoCp: map[string]float64{
			"fluid": 1000.0, // Air-ish volumetric capacity
			"solid": 2000.0, // Solid block capacity
		},
		K: map[string]float64{
			"fluid": 0.026, // Fluid conductivity
			"solid": 10.0,  // Highly conductive block
		},
		HeatSources: map[string]float64{
			"fluid": 0.0,
			"solid": 5000.0, // Heat generation W/m^3 in the block
		},
	}

	cfg.PBCs = []BC{
		NewNeumann("west", 0), NewDirichlet("east", 0),
		NewNeumann("north", 0), NewNeumann("south", 0),
	}
	cfg.UxBCs = []BC{
		NewDirichlet("west", Uin), NewNeumann("east", 0),
		NewDirichlet("north", 0), NewDirichlet("south", 0),
	}
	cfg.UyBCs = []BC{
		NewDirichlet("west", 0), NewNeumann("east", 0),
		NewDirichlet("north", 0), NewDirichlet("south", 0),
	}
	// Thermal BCs: Fixed 300K at inlet, insulated walls, zero gradient at outlet
	cfg.TBCs = []BC{
		NewDirichlet("west", 300.0), NewNeumann("east", 0),
		NewNeumann("north", 0), NewNeumann("south", 0),
	}

	solver, p, Ux, Uy, T := MakeSIMPLE_CHT(mesh, cfg, nil)

	var finalRes float64
	iters := 0
	for i := range 2000 {
		res := solver()
		iters = i + 1
		finalRes = res
		if res < 1e-6 {
			break
		}
	}

	return CHTResult{
		Mesh: mesh, P: p, Ux: Ux, Uy: Uy, T: T,
		Iterations: iters, FinalRes: finalRes,
	}
}

//
// Analytical solutions
//

func PoiseuilleAnalytical(y, H, dpdx, gamma float64) float64 {
	return -dpdx / (2 * gamma) * y * (H - y)
}

func PoiseuilleMaxError(Ux []float64, centroids []geometry.Vec2, xCenter, xTol, H, dpdx, gamma float64) float64 {
	maxErr := 0.0
	for i, c := range centroids {
		if math.Abs(c.X-xCenter) < xTol {
			exact := PoiseuilleAnalytical(c.Y, H, dpdx, gamma)
			err := math.Abs(Ux[i] - exact)
			maxErr = max(maxErr, err)
		}
	}
	return maxErr
}

func CouetteMaxError(Ux []float64, centroids []geometry.Vec2, xCenter, xTol, H, Uwall float64) float64 {
	maxErr := 0.0
	for i, c := range centroids {
		if math.Abs(c.X-xCenter) < xTol {
			exact := Uwall * c.Y / H
			err := math.Abs(Ux[i] - exact)
			maxErr = max(maxErr, err)
		}
	}
	return maxErr
}
