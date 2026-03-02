package fvm

import (
	"fmt"
	"io"

	"jedn.dev/jnlcfd/geometry"
)

//
// Solvers are functions that perform iterations and return residuals
//

type Solver func() (contRes float64)

func MakeSIMPLE(
	mesh *geometry.Mesh,
	gamma, rho float64,
	alphaU, alphaP float64,
	pBCs, uxBCs, uyBCs []BC,
	log io.Writer, // nil to disable
) (solver Solver, p, Ux, Uy []float64) {
	nCells := len(mesh.Centroids)
	nConns := len(mesh.Connections)

	// Cell fields
	p = make([]float64, nCells)
	pPrime := make([]float64, nCells)
	gradPx := make([]float64, nCells)
	gradPy := make([]float64, nCells)
	gradPPrimeX := make([]float64, nCells)
	gradPPrimeY := make([]float64, nCells)

	Ux = make([]float64, nCells)
	Uy = make([]float64, nCells)
	gradUxx := make([]float64, nCells)
	gradUxy := make([]float64, nCells)
	gradUyx := make([]float64, nCells)
	gradUyy := make([]float64, nCells)

	aPx := make([]float64, nCells)
	aPy := make([]float64, nCells)

	divU := make([]float64, nCells)

	// Face fields
	pFace := make([]float64, nConns)
	UxFace := make([]float64, nConns)
	UyFace := make([]float64, nConns)
	UnMWI := make([]float64, nConns)

	// Systems
	pSys := NewFVSystem(mesh)
	UxSys := NewFVSystem(mesh)
	UySys := NewFVSystem(mesh)

	// Initialise aPx/aPy to avoid division by zero on first iteration
	FieldFill(aPx, 1.0)
	FieldFill(aPy, 1.0)

	ppBCs := pPrimeBCs(pBCs)
	volExpr := CellVolExpr(mesh)

	solver = func() float64 {
		// ── Pressure gradient ──
		FaceInterpCDS(mesh, p, pFace)
		applyBCFaceValues(mesh, p, pFace, pBCs)
		GreenGaussGradient(mesh, pFace, gradPx, gradPy)

		// ── Face velocities for convection ──
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)
		applyBCFaceNormals(mesh, Ux, Uy, UnMWI, uxBCs, uyBCs)

		// ── X-Momentum ──
		UxSys.Reset()
		FaceInterpCDS(mesh, Ux, UxFace)
		applyBCFaceValues(mesh, Ux, UxFace, uxBCs)
		GreenGaussGradient(mesh, UxFace, gradUxx, gradUxy)

		DivConstUDS(UxSys, mesh, rho, UnMWI)
		LaplacianConst(UxSys, mesh, gamma, gradUxx, gradUxy)
		SuExpr(UxSys, mesh, NegExpr(FieldExpr(gradPx)))
		applyBCs(UxSys, mesh, uxBCs)

		UxSys.UnderRelax(Ux, alphaU)
		UxSys.CopyDiag(aPx)
		UxSys.SolveBiCGSTAB(Ux, 1e-6, 1000)

		// ── Y-Momentum ──
		UySys.Reset()
		FaceInterpCDS(mesh, Uy, UyFace)
		applyBCFaceValues(mesh, Uy, UyFace, uyBCs)
		GreenGaussGradient(mesh, UyFace, gradUyx, gradUyy)

		DivConstUDS(UySys, mesh, rho, UnMWI)
		LaplacianConst(UySys, mesh, gamma, gradUyx, gradUyy)
		SuExpr(UySys, mesh, NegExpr(FieldExpr(gradPy)))
		applyBCs(UySys, mesh, uyBCs)

		UySys.UnderRelax(Uy, alphaU)
		UySys.CopyDiag(aPy)
		UySys.SolveBiCGSTAB(Uy, 1e-6, 1000)

		// ── Pressure correction ──
		pSys.Reset()
		FieldZero(pPrime)

		FaceInterpCDS(mesh, pPrime, pFace)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		dExpr := DivExpr(volExpr, FieldExpr(aPx))
		LaplacianExpr(pSys, mesh, dExpr, gradPPrimeX, gradPPrimeY)

		// Recompute U* face velocities for divergence source
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)
		applyBCFaceNormals(mesh, Ux, Uy, UnMWI, uxBCs, uyBCs)

		Divergence(mesh, UnMWI, divU)
		SuFieldScaled(pSys, -rho, divU)
		applyBCs(pSys, mesh, ppBCs)

		if log != nil {
			fmt.Fprintf(log, "  aPx: [%.3e, %.3e]  p' diag: [%.3e, %.3e]  RHS sum: %.3e\n",
				minSlice(aPx), maxSlice(aPx),
				minSlice(pSys.Matrix.diag), maxSlice(pSys.Matrix.diag),
				sumSlice(pSys.Rhs))
		}

		pSys.SolveCG(pPrime, 1e-6, 1000)

		// ── Corrections ──
		FaceInterpCDS(mesh, pPrime, pFace)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		MulExpr(DivExpr(volExpr, FieldExpr(aPx)), FieldExpr(gradPPrimeX)).SubFrom(Ux)
		MulExpr(DivExpr(volExpr, FieldExpr(aPy)), FieldExpr(gradPPrimeY)).SubFrom(Uy)
		ScaleExpr(FieldExpr(pPrime), alphaP).AddInto(p)

		if log != nil {
			fmt.Fprintf(log, "  |p'|: [%.3e, %.3e]  |ΔUx|: %.3e  |ΔUy|: %.3e\n",
				minSlice(pPrime), maxSlice(pPrime),
				NormLInf(gradPPrimeX), NormLInf(gradPPrimeY))
		}

		return NormL1(divU) * rho
	}

	return
}

func MakeSIMPLEStokes(
	mesh *geometry.Mesh,
	gamma, rho float64,
	alphaU, alphaP float64,
	pBCs, uxBCs, uyBCs []BC,
) (solver Solver, p, Ux, Uy []float64) {
	nCells := len(mesh.Centroids)
	nConns := len(mesh.Connections)

	// Cell fields
	p = make([]float64, nCells)
	pPrime := make([]float64, nCells)
	gradPx := make([]float64, nCells)
	gradPy := make([]float64, nCells)
	gradPPrimeX := make([]float64, nCells)
	gradPPrimeY := make([]float64, nCells)

	Ux = make([]float64, nCells)
	Uy = make([]float64, nCells)
	gradUxx := make([]float64, nCells)
	gradUxy := make([]float64, nCells)
	gradUyx := make([]float64, nCells)
	gradUyy := make([]float64, nCells)

	aPx := make([]float64, nCells)
	aPy := make([]float64, nCells)

	divU := make([]float64, nCells) // for continuity residual

	// face fields
	pFace := make([]float64, nConns)
	UxFace := make([]float64, nConns)
	UyFace := make([]float64, nConns)
	UnMWI := make([]float64, nConns)

	// Systems
	pSys := NewFVSystem(mesh)
	UxSys := NewFVSystem(mesh)
	UySys := NewFVSystem(mesh)

	// Initialise aPx/aPy to avoid division by zero
	FieldFill(aPx, 1.0)
	FieldFill(aPy, 1.0)

	ppBCs := pPrimeBCs(pBCs)
	volExpr := CellVolExpr(mesh)

	solver = func() float64 {
		// Update pressure gradients initially
		FaceInterpCDS(mesh, p, pFace)
		applyBCFaceValues(mesh, p, pFace, pBCs)
		GreenGaussGradient(mesh, pFace, gradPx, gradPy)

		// Face velocities for convection
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)
		applyBCFaceNormals(mesh, Ux, Uy, UnMWI, uxBCs, uyBCs)

		// X-Momentum
		UxSys.Reset()

		FaceInterpCDS(mesh, Ux, UxFace)
		applyBCFaceValues(mesh, Ux, UxFace, uxBCs)
		GreenGaussGradient(mesh, UxFace, gradUxx, gradUxy)

		LaplacianConst(UxSys, mesh, gamma, gradUxx, gradUxy)
		SuExpr(UxSys, mesh, NegExpr(FieldExpr(gradPx)))

		applyBCs(UxSys, mesh, uxBCs)

		UxSys.CopyDiag(aPx)
		UxSys.UnderRelax(Ux, alphaU)
		UxSys.SolveBiCGSTAB(Ux, 1e-6, 1000)

		// Y-Momentum
		UySys.Reset()

		FaceInterpCDS(mesh, Uy, UyFace)
		applyBCFaceValues(mesh, Uy, UyFace, uyBCs)
		GreenGaussGradient(mesh, UyFace, gradUyx, gradUyy)

		LaplacianConst(UySys, mesh, gamma, gradUyx, gradUyy)
		SuExpr(UySys, mesh, NegExpr(FieldExpr(gradPy)))

		applyBCs(UySys, mesh, uyBCs)

		UySys.CopyDiag(aPy)
		UySys.UnderRelax(Uy, alphaU)
		UySys.SolveBiCGSTAB(Uy, 1e-6, 1000)

		// Pressure correction
		pSys.Reset()
		FieldZero(pPrime)

		FaceInterpCDS(mesh, pPrime, pFace)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		dExpr := DivExpr(volExpr, FieldExpr(aPx))
		LaplacianExpr(pSys, mesh, dExpr, gradPPrimeX, gradPPrimeY)

		// From earlier solve for U*
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)
		applyBCFaceNormals(mesh, Ux, Uy, UnMWI, uxBCs, uyBCs)

		// Divergence for RHS and continuity residual
		Divergence(mesh, UnMWI, divU)
		SuFieldScaled(pSys, -rho, divU)

		applyBCs(pSys, mesh, ppBCs)
		pSys.SolveCG(pPrime, 1e-6, 1000)

		// Corrections
		FaceInterpCDS(mesh, pPrime, pFace)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		MulExpr(DivExpr(volExpr, FieldExpr(aPx)), FieldExpr(gradPPrimeX)).SubFrom(Ux)
		MulExpr(DivExpr(volExpr, FieldExpr(aPy)), FieldExpr(gradPPrimeY)).SubFrom(Uy)
		ScaleExpr(FieldExpr(pPrime), alphaP).AddInto(p)

		return NormL1(divU) * rho
	}

	return
}

//
// CHT
//

// CHTConfig defines the properties, regions, and boundaries for a Conjugate Heat Transfer solve.
type CHTConfig struct {
	FluidRegions []string
	SolidRegions []string

	PBCs  []BC
	UxBCs []BC
	UyBCs []BC
	TBCs  []BC

	// Fluid Dynamics Properties
	RhoFluid  float64
	NuFluid   float64 // Kinematic viscosity
	BetaFluid float64 // Thermal expansion coefficient
	Tref      float64 // Reference temperature
	Gx, Gy    float64 // Gravity vector for buoyancy

	UseBuoyancy bool // Toggle buoyancy term

	// Under-relaxation
	AlphaU float64
	AlphaP float64
	AlphaT float64

	// Thermal Properties (mapped by Region Name)
	RhoCp       map[string]float64 // Volumetric heat capacity: rho * Cp
	K           map[string]float64 // Thermal conductivity
	HeatSources map[string]float64 // Volumetric heat source: W/m^3
}

func MakeSIMPLE_CHT(
	mesh *geometry.Mesh,
	cfg CHTConfig,
	log io.Writer,
) (solver Solver, p, Ux, Uy, T []float64) {
	nCells := len(mesh.Centroids)
	nConns := len(mesh.Connections)

	// Fields
	p = make([]float64, nCells)
	pPrime := make([]float64, nCells)
	gradPx := make([]float64, nCells)
	gradPy := make([]float64, nCells)
	gradPPrimeX := make([]float64, nCells)
	gradPPrimeY := make([]float64, nCells)

	Ux = make([]float64, nCells)
	Uy = make([]float64, nCells)
	gradUxx := make([]float64, nCells)
	gradUxy := make([]float64, nCells)
	gradUyx := make([]float64, nCells)
	gradUyy := make([]float64, nCells)

	T = make([]float64, nCells)
	TFace := make([]float64, nConns)
	gradTx := make([]float64, nCells)
	gradTy := make([]float64, nCells)

	aPx := make([]float64, nCells)
	aPy := make([]float64, nCells)
	divU := make([]float64, nCells)

	// Face fields
	pFace := make([]float64, nConns)
	UxFace := make([]float64, nConns)
	UyFace := make([]float64, nConns)
	UnMWI := make([]float64, nConns)

	// Systems
	pSys := NewFVSystem(mesh)
	UxSys := NewFVSystem(mesh)
	UySys := NewFVSystem(mesh)
	TSys := NewFVSystem(mesh)

	FieldFill(aPx, 1.0)
	FieldFill(aPy, 1.0)
	FieldFill(T, cfg.Tref) // Initialize temperature

	ppBCs := pPrimeBCs(cfg.PBCs)
	volExpr := CellVolExpr(mesh)

	// ── Structure & Masks ──

	// Mask out solids: 1.0 in fluid, 0.0 in solid
	fluidMask := make([]float64, nCells)
	solidMask := RegionsFromNames(mesh, cfg.SolidRegions...)
	for i := range fluidMask {
		if !solidMask.Contains(mesh.CellRegions[i]) {
			fluidMask[i] = 1.0
		}
	}
	fluidMaskExpr := FieldExpr(fluidMask)

	// Mask out face fluxes touching solids to enforce zero penetration
	faceFluidMask := make([]float64, nConns)
	for i, conn := range mesh.Connections {
		isSolid := solidMask.Contains(mesh.CellRegions[conn.Owner])
		if conn.Neighbour >= 0 && solidMask.Contains(mesh.CellRegions[conn.Neighbour]) {
			isSolid = true
		}
		if !isSolid {
			faceFluidMask[i] = 1.0
		}
	}
	faceMaskExpr := FieldExpr(faceFluidMask)

	solidCells := CellsInRegions(mesh, cfg.SolidRegions...)

	// ── Property Expressions ──

	kMap := make(map[string]Expression)
	rhoCpMap := make(map[string]Expression)
	qMap := make(map[string]Expression)

	for _, reg := range append(cfg.SolidRegions, cfg.FluidRegions...) {
		kMap[reg] = ConstExpr(cfg.K[reg])
		rhoCpMap[reg] = ConstExpr(cfg.RhoCp[reg])
		qMap[reg] = ConstExpr(cfg.HeatSources[reg])
	}

	kExpr := RegionExpr(mesh, kMap, ConstExpr(0.0))
	rhoCpExpr := RegionExpr(mesh, rhoCpMap, ConstExpr(1.0))
	qExpr := RegionExpr(mesh, qMap, ConstExpr(0.0))

	boussinesqX := BoussinesqExpr(cfg.RhoFluid, cfg.BetaFluid, cfg.Tref, cfg.Gx, FieldExpr(T))
	boussinesqY := BoussinesqExpr(cfg.RhoFluid, cfg.BetaFluid, cfg.Tref, cfg.Gy, FieldExpr(T))

	// ── CHT Interface Helper ──
	// Fixes face values at the fluid-solid boundary before gradient calculation
	fixFluidSolidFaces := func(field, faceField []float64, isPressure bool) {
		for i, conn := range mesh.Connections {
			if conn.Neighbour < 0 {
				continue
			}
			ownerIsSolid := solidMask.Contains(mesh.CellRegions[conn.Owner])
			neighIsSolid := solidMask.Contains(mesh.CellRegions[conn.Neighbour])

			if ownerIsSolid != neighIsSolid {
				// We are at the fluid-solid interface!
				if isPressure {
					// Zero-gradient boundary: face takes the value of the fluid cell
					if ownerIsSolid {
						faceField[i] = field[conn.Neighbour]
					} else {
						faceField[i] = field[conn.Owner]
					}
				} else {
					// No-slip boundary: face velocity is strictly zero
					faceField[i] = 0.0
				}
			}
		}
	}

	// ── Solver Iteration ──
	solver = func() float64 {
		// ── Pressure gradient ──
		FaceInterpCDS(mesh, p, pFace)
		fixFluidSolidFaces(p, pFace, true)
		applyBCFaceValues(mesh, p, pFace, cfg.PBCs)
		GreenGaussGradient(mesh, pFace, gradPx, gradPy)

		// ── Face velocities for convection ──
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)
		applyBCFaceNormals(mesh, Ux, Uy, UnMWI, cfg.UxBCs, cfg.UyBCs)
		MulExpr(FieldExpr(UnMWI), faceMaskExpr).Apply(UnMWI) // Cut off solid faces algebraically

		// ── X-Momentum ──
		UxSys.Reset()
		FaceInterpCDS(mesh, Ux, UxFace)
		fixFluidSolidFaces(Ux, UxFace, false)
		applyBCFaceValues(mesh, Ux, UxFace, cfg.UxBCs)
		GreenGaussGradient(mesh, UxFace, gradUxx, gradUxy)

		DivConstUDS(UxSys, mesh, cfg.RhoFluid, UnMWI)
		LaplacianConst(UxSys, mesh, cfg.NuFluid*cfg.RhoFluid, gradUxx, gradUxy)
		SuExpr(UxSys, mesh, NegExpr(FieldExpr(gradPx)), cfg.FluidRegions...)
		if cfg.UseBuoyancy {
			SuExpr(UxSys, mesh, boussinesqX, cfg.FluidRegions...)
		}
		applyBCs(UxSys, mesh, cfg.UxBCs)

		UxSys.PinCells(solidCells, 0.0) // Lock solid velocity to 0
		UxSys.UnderRelax(Ux, cfg.AlphaU)
		UxSys.CopyDiag(aPx)
		UxSys.SolveBiCGSTAB(Ux, 1e-6, 1000)

		// ── Y-Momentum ──
		UySys.Reset()
		FaceInterpCDS(mesh, Uy, UyFace)
		fixFluidSolidFaces(Uy, UyFace, false)
		applyBCFaceValues(mesh, Uy, UyFace, cfg.UyBCs)
		GreenGaussGradient(mesh, UyFace, gradUyx, gradUyy)

		DivConstUDS(UySys, mesh, cfg.RhoFluid, UnMWI)
		LaplacianConst(UySys, mesh, cfg.NuFluid*cfg.RhoFluid, gradUyx, gradUyy)
		SuExpr(UySys, mesh, NegExpr(FieldExpr(gradPy)), cfg.FluidRegions...)
		if cfg.UseBuoyancy {
			SuExpr(UySys, mesh, boussinesqY, cfg.FluidRegions...)
		}
		applyBCs(UySys, mesh, cfg.UyBCs)

		UySys.PinCells(solidCells, 0.0) // Lock solid velocity to 0
		UySys.UnderRelax(Uy, cfg.AlphaU)
		UySys.CopyDiag(aPy)
		UySys.SolveBiCGSTAB(Uy, 1e-6, 1000)

		// ── Pressure correction ──
		pSys.Reset()
		FieldZero(pPrime)

		FaceInterpCDS(mesh, pPrime, pFace)
		fixFluidSolidFaces(pPrime, pFace, true)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		dExpr := MulExpr(fluidMaskExpr, DivExpr(volExpr, FieldExpr(aPx)))
		LaplacianExprHarmonic(pSys, mesh, dExpr, gradPPrimeX, gradPPrimeY)

		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)
		applyBCFaceNormals(mesh, Ux, Uy, UnMWI, cfg.UxBCs, cfg.UyBCs)
		MulExpr(FieldExpr(UnMWI), faceMaskExpr).Apply(UnMWI)

		Divergence(mesh, UnMWI, divU)
		SuFieldScaled(pSys, -cfg.RhoFluid, divU)
		applyBCs(pSys, mesh, ppBCs)

		pSys.PinCells(solidCells, 0.0) // Isolate pressure changes from solid
		pSys.SolveCG(pPrime, 1e-6, 1000)

		// ── Corrections (Algebraic Masking) ──
		FaceInterpCDS(mesh, pPrime, pFace)
		fixFluidSolidFaces(pPrime, pFace, true)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		MulExpr(fluidMaskExpr, MulExpr(DivExpr(volExpr, FieldExpr(aPx)), FieldExpr(gradPPrimeX))).SubFrom(Ux)
		MulExpr(fluidMaskExpr, MulExpr(DivExpr(volExpr, FieldExpr(aPy)), FieldExpr(gradPPrimeY))).SubFrom(Uy)
		MulExpr(fluidMaskExpr, ScaleExpr(FieldExpr(pPrime), cfg.AlphaP)).AddInto(p)

		// ── Temperature Equation (Domain Wide) ──
		TSys.Reset()
		FaceInterpCDS(mesh, T, TFace)
		applyBCFaceValues(mesh, T, TFace, cfg.TBCs)
		GreenGaussGradient(mesh, TFace, gradTx, gradTy)

		DivExprUDS(TSys, mesh, rhoCpExpr, UnMWI)
		LaplacianExprHarmonic(TSys, mesh, kExpr, gradTx, gradTy)
		SuExpr(TSys, mesh, qExpr)
		applyBCs(TSys, mesh, cfg.TBCs)

		TSys.UnderRelax(T, cfg.AlphaT)
		TSys.SolveBiCGSTAB(T, 1e-6, 1000)

		if log != nil {
			fmt.Fprintf(log, "  |p'|: [%.3e, %.3e]  |ΔUx|: %.3e  |ΔUy|: %.3e  |T|: [%.1f, %.1f]\n",
				minSlice(pPrime), maxSlice(pPrime),
				NormLInf(gradPPrimeX), NormLInf(gradPPrimeY),
				minSlice(T), maxSlice(T))
		}

		return NormL1(divU) * cfg.RhoFluid
	}

	return
}

//
// Helpers
//

func pPrimeBCs(pBCs []BC) []BC {
	ppBCs := make([]BC, len(pBCs))
	for i, bc := range pBCs {
		if bc.Type == Dirichlet {
			// p is fixed here, so p' correction must be zero
			ppBCs[i] = BC{bc.Boundary, Dirichlet, 0.0}
		} else {
			// Neumann/zeroGradient passes through unchanged
			ppBCs[i] = bc
		}
	}
	return ppBCs
}

func minSlice(s []float64) float64 {
	m := s[0]
	for _, v := range s[1:] {
		if v < m {
			m = v
		}
	}
	return m
}

func maxSlice(s []float64) float64 {
	m := s[0]
	for _, v := range s[1:] {
		if v > m {
			m = v
		}
	}
	return m
}

func sumSlice(s []float64) float64 {
	sum := 0.0
	for _, v := range s {
		sum += v
	}
	return sum
}
