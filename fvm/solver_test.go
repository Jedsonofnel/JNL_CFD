package fvm

import (
	"math"
	"slices"
	"testing"

	"jedn.dev/jnlcfd/geometry"
)

//
// SIMPLE tests
//

func TestSingleSIMPLEStep(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 400, 30)

	pBCs := []BC{
		NewDirichlet("west", 1.0), NewDirichlet("east", 0.0),
		NewNeumann("north", 0), NewNeumann("south", 0),
	}
	uxBCs := []BC{
		NewNeumann("west", 0), NewNeumann("east", 0),
		NewDirichlet("north", 0), NewDirichlet("south", 0),
	}
	uyBCs := []BC{
		NewDirichlet("west", 0), NewDirichlet("east", 0),
		NewDirichlet("north", 0), NewDirichlet("south", 0),
	}

	solver, _, Ux, _ := MakeSIMPLEStokes(mesh, 1.0, 1.0, 0.7, 0.3, pBCs, uxBCs, uyBCs)

	residuals := make([]float64, 10)
	for i := range residuals {
		residuals[i] = solver()
		t.Logf("Iter %d: res = %.4e", i, residuals[i])
	}

	// Check: does residual decrease in at least the first few steps?
	if residuals[1] > residuals[0] {
		t.Errorf("Residual increased on first step: %.4e -> %.4e", residuals[0], residuals[1])
	}

	// Also check velocity is physically reasonable
	maxUx := 0.0
	for _, u := range Ux {
		maxUx = max(maxUx, math.Abs(u))
	}
	t.Logf("Max |Ux| after 10 iters: %.4e", maxUx)
	t.Logf("Expected Poiseuille max: %.4e", 0.25/(2.0)*0.25) // dpdx * H^2 / 8
}

func TestSIMPLEStability(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 400, 30)

	pBCs := []BC{
		NewDirichlet("west", 1.0), NewDirichlet("east", 0.0),
		NewNeumann("north", 0), NewNeumann("south", 0),
	}
	uxBCs := []BC{
		NewNeumann("west", 0), NewNeumann("east", 0),
		NewDirichlet("north", 0), NewDirichlet("south", 0),
	}
	uyBCs := []BC{
		NewDirichlet("west", 0), NewDirichlet("east", 0),
		NewDirichlet("north", 0), NewDirichlet("south", 0),
	}

	solver, p, Ux, Uy := MakeSIMPLEStokes(mesh, 1.0, 1.0, 0.7, 0.3, pBCs, uxBCs, uyBCs)

	prevRes := math.Inf(1)
	for i := range 200 {
		res := solver()
		if i%10 == 0 {
			maxUx, maxUy, maxP := 0.0, 0.0, 0.0
			for j := range Ux {
				maxUx = max(maxUx, math.Abs(Ux[j]))
				maxUy = max(maxUy, math.Abs(Uy[j]))
				maxP = max(maxP, math.Abs(p[j]))
			}
			t.Logf("Iter %3d: res=%.2e  maxUx=%.2e  maxUy=%.2e  maxP=%.2e",
				i, res, maxUx, maxUy, maxP)
		}
		if res > 10*prevRes && res > 1e-4 {
			t.Errorf("Divergence detected at iter %d: %.2e -> %.2e", i, prevRes, res)
			break
		}
		prevRes = res
	}
}

func TestStokesChannel(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 400, 30)

	gamma := 1.0
	rho := 1.0

	// Pressure-driven channel flow
	pBCs := []BC{
		NewDirichlet("west", 1.0), // inlet pressure
		NewDirichlet("east", 0.0), // outlet pressure
		NewNeumann("north", 0),
		NewNeumann("south", 0),
	}
	uxBCs := []BC{
		NewNeumann("west", 0),    // developed flow
		NewNeumann("east", 0),    // developed flow
		NewDirichlet("north", 0), // no-slip wall
		NewDirichlet("south", 0), // no-slip wall
	}
	uyBCs := []BC{
		NewDirichlet("west", 0),
		NewDirichlet("east", 0),
		NewDirichlet("north", 0),
		NewDirichlet("south", 0),
	}

	solver, p, Ux, Uy := MakeSIMPLEStokes(mesh, gamma, rho, 0.7, 0.3, pBCs, uxBCs, uyBCs)

	var finalRes float64
	for iter := range 500 {
		res := solver()
		if iter%50 == 0 || res < 1e-6 {
			t.Logf("Iter %3d: continuity res = %.2e", iter, res)
		}
		finalRes = res
		if res < 1e-6 {
			break
		}
	}

	if finalRes > 1e-4 {
		t.Errorf("SIMPLE didn't converge, final residual = %.2e", finalRes)
	}

	// Check Poiseuille profile at channel center (x=2)
	dpdx := -0.25 // (0 - 1) / 4
	H := 1.0

	t.Logf("\nVelocity profile at x=2:")
	maxErr := 0.0
	for i, c := range mesh.Centroids {
		if math.Abs(c.X-2.0) < 0.2 {
			exact := -dpdx / (2 * gamma) * c.Y * (H - c.Y)
			err := math.Abs(Ux[i] - exact)
			maxErr = max(maxErr, err)
		}
	}
	t.Logf("Max velocity error: %.4f", maxErr)

	_ = p
	_ = Uy
}

//
// Component Tests
//

func TestStokesMomentumAlone(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 400, 30)

	gamma := 1.0
	H := 1.0
	dpdx := -0.25

	nCells := len(mesh.Centroids)
	t.Logf("Num cells = %d\n", nCells)
	Ux := make([]float64, nCells)

	uxBCs := []BC{
		NewNeumann("west", 0),
		NewNeumann("east", 0),
		NewDirichlet("north", 0),
		NewDirichlet("south", 0),
	}

	gradUxx := make([]float64, nCells)
	gradUxy := make([]float64, nCells)
	UxFace := make([]float64, len(mesh.Connections))

	// Iterate non-orthogonal corrections
	sys := NewFVSystem(mesh)
	for range 10 {
		sys.Reset()

		FaceInterpCDS(mesh, Ux, UxFace)
		applyBCFaceValues(mesh, Ux, UxFace, uxBCs)
		GreenGaussGradient(mesh, UxFace, gradUxx, gradUxy)

		LaplacianConst(sys, mesh, gamma, gradUxx, gradUxy)
		SuConst(sys, mesh, -dpdx) // dp/dx as volume source
		applyBCs(sys, mesh, uxBCs)
		sys.SolveCG(Ux, 1e-10, 1000)
	}

	maxErr := 0.0
	for i, c := range mesh.Centroids {
		exact := -dpdx / (2 * gamma) * c.Y * (H - c.Y)
		err := math.Abs(Ux[i] - exact)
		maxErr = max(maxErr, err)
	}

	t.Logf("Max Poiseuille error: %.4e", maxErr)
	if maxErr > 0.05 {
		t.Errorf("Momentum equation alone doesn't recover Poiseuille, max error = %.4e", maxErr)
	}
}

// ∇²p = f with manufactured solution p = sin(πx)sin(πy)
// Then ∇²p = -2π²sin(πx)sin(πy)
func TestPressurePoissonManufactured(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 1, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 500, 30)

	nCells := len(mesh.Centroids)
	p := make([]float64, nCells)

	sys := NewFVSystem(mesh)
	LaplacianConst(sys, mesh, 1.0, nil, nil)

	// Source term: -2π²sin(πx)sin(πy)
	for i, c := range mesh.Centroids {
		sys.Rhs[i] += 2 * math.Pi * math.Pi * math.Sin(math.Pi*c.X) * math.Sin(math.Pi*c.Y) * mesh.CellVolumes[i]
	}

	// Dirichlet p=0 on all boundaries (matches sin(πx)sin(πy) at boundaries)
	DirichletConstBC(sys, mesh, 0, "south")
	DirichletConstBC(sys, mesh, 0, "north")
	DirichletConstBC(sys, mesh, 0, "east")
	DirichletConstBC(sys, mesh, 0, "west")

	sys.SolveCG(p, 1e-10, 1000)

	// Check against analytical
	maxErr := 0.0
	for i, c := range mesh.Centroids {
		exact := math.Sin(math.Pi*c.X) * math.Sin(math.Pi*c.Y)
		err := math.Abs(p[i] - exact)
		maxErr = max(maxErr, err)
	}

	t.Logf("Pressure Poisson max error: %.2e", maxErr)
	if maxErr > 0.1 {
		t.Errorf("Pressure Poisson too inaccurate")
	}
}

func TestPressurePoissonConvergence(t *testing.T) {
	cellCounts := []int{100, 400, 1600}
	errors := make([]float64, len(cellCounts))
	h := make([]float64, len(cellCounts))

	for idx, targetCells := range cellCounts {
		db := geometry.DomainBuilder{}
		db.AddPolygon(geometry.MakeRectangle(0, 0, 1, 1, "fluid", "south", "east", "north", "west"))
		domain, _ := db.Build()
		mesh, _ := geometry.MeshWithCells(domain, targetCells, 30)

		nCells := len(mesh.Centroids)
		h[idx] = 1.0 / math.Sqrt(float64(nCells))
		p := make([]float64, nCells)

		sys := NewFVSystem(mesh)
		LaplacianConst(sys, mesh, 1.0, nil, nil)

		for i, c := range mesh.Centroids {
			sys.Rhs[i] += 2 * math.Pi * math.Pi * math.Sin(math.Pi*c.X) * math.Sin(math.Pi*c.Y) * mesh.CellVolumes[i]
		}

		DirichletConstBC(sys, mesh, 0, "south")
		DirichletConstBC(sys, mesh, 0, "north")
		DirichletConstBC(sys, mesh, 0, "east")
		DirichletConstBC(sys, mesh, 0, "west")

		sys.SolveCG(p, 1e-10, 1000)

		maxErr := 0.0
		for i, c := range mesh.Centroids {
			exact := math.Sin(math.Pi*c.X) * math.Sin(math.Pi*c.Y)
			err := math.Abs(p[i] - exact)
			maxErr = max(maxErr, err)
		}
		errors[idx] = maxErr
	}

	t.Logf("%8s %12s %12s %8s", "nCells", "h", "maxError", "order")
	t.Logf("%8d %12.4f %12.4e %8s", cellCounts[0], h[0], errors[0], "-")

	for i := 1; i < len(cellCounts); i++ {
		order := math.Log(errors[i-1]/errors[i]) / math.Log(h[i-1]/h[i])
		t.Logf("%8d %12.4f %12.4e %8.2f", cellCounts[i], h[i], errors[i], order)
	}
}

// Test: Does p' correction reduce divergence?
func TestVelocityCorrection(t *testing.T) {
	mesh := geometry.MakeSimple1DMesh(20)
	nCells := len(mesh.Centroids)
	nConns := len(mesh.Connections)

	// Start with divergent velocity: Ux = x
	Ux := make([]float64, nCells)
	for i, c := range mesh.Centroids {
		Ux[i] = c.X
	}
	Uy := make([]float64, nCells)

	aPx := make([]float64, nCells)
	aPy := make([]float64, nCells)
	for i := range aPx {
		aPx[i] = 1.0
		aPy[i] = 1.0
	}

	UxFace := make([]float64, nConns)
	UyFace := make([]float64, nConns)
	UnFace := make([]float64, nConns)

	// Use zero-gradient at outlet so correction can affect it
	uxBCs := []BC{
		NewDirichlet("west", 0), // inlet fixed
		NewNeumann("east", 0),   // outlet: zero gradient, NOT fixed
	}

	FaceInterpCDS(mesh, Ux, UxFace)
	FaceInterpCDS(mesh, Uy, UyFace)
	applyBCFaceValues(mesh, Ux, UxFace, uxBCs)
	FaceNormalComponent(mesh, UxFace, UyFace, UnFace)

	divU := make([]float64, nCells)
	Divergence(mesh, UnFace, divU)
	initialDiv := NormL1(divU)
	t.Logf("Initial divergence L1: %.4f", initialDiv)

	// Log face velocities
	t.Logf("Initial face velocities:")
	for i, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			bndName := mesh.BoundaryNames[-int(conn.Neighbour)]
			t.Logf("  Face %d (boundary %s): Un=%.4f", i, bndName, UnFace[i])
		}
	}

	// Pressure correction
	pPrime := make([]float64, nCells)
	gradPPx := make([]float64, nCells)
	gradPPy := make([]float64, nCells)
	pFace := make([]float64, nConns)

	ppBCs := []BC{
		NewNeumann("west", 0),   // p' zero-gradient at inlet
		NewDirichlet("east", 0), // p' = 0 at outlet (fixes pressure level)
	}

	sys := NewFVSystem(mesh)
	dExpr := DivExpr(CellVolExpr(mesh), FieldExpr(aPx))
	LaplacianExpr(sys, mesh, dExpr, nil, nil)
	SuFieldScaled(sys, -1.0, divU)
	applyBCs(sys, mesh, ppBCs)
	sys.SolveCG(pPrime, 1e-10, 1000)

	t.Logf("p' range: [%.4f, %.4f]", slices.Min(pPrime), slices.Max(pPrime))
	t.Logf("p' values: %v", pPrime[:5]) // first few cells

	// Compute grad(p')
	FaceInterpCDS(mesh, pPrime, pFace)
	applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
	GreenGaussGradient(mesh, pFace, gradPPx, gradPPy)

	t.Logf("grad(p') range: [%.4f, %.4f]", slices.Min(gradPPx), slices.Max(gradPPx))

	// Correct CELL velocities
	for i := range Ux {
		d := mesh.CellVolumes[i] / aPx[i]
		Ux[i] -= d * gradPPx[i]
	}

	t.Logf("Corrected Ux range: [%.4f, %.4f]", slices.Min(Ux), slices.Max(Ux))

	// IMPORTANT: Also need to correct FACE velocities directly for internal faces
	// This is what Rhie-Chow does - it adds face-level pressure correction
	// For now, let's just re-interpolate and see what happens

	FaceInterpCDS(mesh, Ux, UxFace)
	FaceInterpCDS(mesh, Uy, UyFace)
	applyBCFaceValues(mesh, Ux, UxFace, uxBCs)

	t.Logf("Corrected face velocities:")
	for i, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			bndName := mesh.BoundaryNames[-int(conn.Neighbour)]
			t.Logf("  Face %d (boundary %s): Ux=%.4f", i, bndName, UxFace[i])
		}
	}

	FaceNormalComponent(mesh, UxFace, UyFace, UnFace)
	Divergence(mesh, UnFace, divU)

	finalDiv := NormL1(divU)
	t.Logf("Final divergence L1: %.4f", finalDiv)
	t.Logf("Divergence reduction: %.2fx", initialDiv/(finalDiv+1e-30))

	if finalDiv > 0.1*initialDiv {
		t.Errorf("Velocity correction didn't reduce divergence enough")
	}
}

func TestPressureSign(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()

	mesh, _ := geometry.MeshWithCells(domain, 100, 10) // Small mesh
	sys := NewFVSystem(mesh)

	// 1. Assemble Laplacian (Standard diffusion)
	LaplacianConst(sys, mesh, 1.0, nil, nil)

	// 2. Set a MASS SURPLUS in the center cell
	centerCell := len(mesh.Centroids) / 2
	sys.Rhs[centerCell] = 1.0 // This mimics "div(U*) > 0"

	// 3. Solve for p' (use Dirichlet BCs on all sides to make it well-posed)
	DirichletConstBC(sys, mesh, 0, "north")
	DirichletConstBC(sys, mesh, 0, "south")
	DirichletConstBC(sys, mesh, 0, "east")
	DirichletConstBC(sys, mesh, 0, "west")
	pPrime := make([]float64, len(mesh.Centroids))
	sys.SolveCG(pPrime, 1e-10, 1000)

	// 4. CHECK SIGN
	// If Laplacian diag is POSITIVE, and Rhs is POSITIVE,
	// then pPrime at the center MUST be POSITIVE.
	if pPrime[centerCell] < 0 {
		t.Errorf("SIGN ERROR: Mass surplus resulted in negative pressure correction. " +
			"Flip the sign of your SuFieldScaled source term!")
	}
}
