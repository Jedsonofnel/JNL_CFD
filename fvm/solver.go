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
