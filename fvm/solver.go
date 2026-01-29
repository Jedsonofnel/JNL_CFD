package fvm

import (
	"fmt"
	"math"

	"jedn.dev/jnlcfd/geometry"
)

//
// Solvers are functions that perform iterations and return residuals
//

type NSSolver func() (contRes float64)

func MakeSIMPLE(
	mesh *geometry.Mesh,
	gamma, rho float64,
	alphaU, alphaP float64,
	pBCs, uxBCs, uyBCs []BC,
) (solver NSSolver, p, Ux, Uy []float64) {
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

	// TODO can I remove these by directly using the matrix.diag slices?
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

	// initalise aPx/aPy to avoid division by zero
	for i := range aPx {
		aPx[i] = 1.0
		aPy[i] = 1.0
	}

	ppBCs := pPrimeBCs(pBCs)
	needsPressureRef := !hasDirichletBC(pBCs)

	solver = func() float64 {
		// Face velocities for convection
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)

		// X-Momentum
		UxSys.Reset()

		FaceInterpCDS(mesh, Ux, UxFace)
		applyBCFaceValues(mesh, Ux, UxFace, uxBCs)
		GreenGaussGradient(mesh, UxFace, gradUxx, gradUxy)

		DivConstUDS(UxSys, mesh, rho, UnMWI)
		LaplacianConst(UxSys, mesh, gamma, gradUxx, gradUxy)
		SuExpr(UxSys, mesh, NegExpr(FieldExpr(gradPx)))

		applyBCs(UxSys, mesh, uxBCs)

		copy(aPx, UxSys.Matrix.diag)
		UxSys.UnderRelax(Ux, alphaU)

		fmt.Printf("  UxSys: diagDom=%.3f minDiag=%.3e symmetric=%.3e\n",
			UxSys.DiagonalDominanceRatio(),
			UxSys.MinDiagonal(),
			UxSys.MaxAsymmetry())

		UxSys.SolveBiCGSTAB(Ux, 1e-6, 1000)

		// Y-Momentum
		UySys.Reset()

		FaceInterpCDS(mesh, Uy, UyFace)
		applyBCFaceValues(mesh, Uy, UyFace, uyBCs)
		GreenGaussGradient(mesh, UyFace, gradUyx, gradUyy)

		DivConstUDS(UySys, mesh, rho, UnMWI)
		LaplacianConst(UySys, mesh, gamma, gradUyx, gradUyy)
		SuExpr(UySys, mesh, NegExpr(FieldExpr(gradPy)))

		applyBCs(UySys, mesh, uyBCs)

		copy(aPy, UySys.Matrix.diag)
		UySys.UnderRelax(Uy, alphaU)

		fmt.Printf("  UySys: diagDom=%.3f minDiag=%.3e symmetric=%.3e\n",
			UySys.DiagonalDominanceRatio(),
			UySys.MinDiagonal(),
			UySys.MaxAsymmetry())

		UySys.SolveBiCGSTAB(Uy, 1e-6, 1000)

		// Pressure correction
		pSys.Reset()

		FaceInterpCDS(mesh, pPrime, pFace)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		dExpr := DivExpr(CellVolExpr(mesh), FieldExpr(aPx))
		LaplacianExpr(pSys, mesh, dExpr, gradPPrimeX, gradPPrimeY)

		// From earlier solve for U*
		RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnMWI)

		// Divergence for RHS and continuity residual
		Divergence(mesh, UnMWI, divU)
		SuFieldScaled(pSys, -rho, divU)

		applyBCs(pSys, mesh, ppBCs) // uses p' BCs rather than p

		fmt.Printf("  pSys: diagDom=%.3f minDiag=%.3e symmetric=%.3e rhsNorm=%.3e\n",
			pSys.DiagonalDominanceRatio(),
			pSys.MinDiagonal(),
			pSys.MaxAsymmetry(),
			pSys.RHSNorm())

		pSys.SolveCG(pPrime, 1e-6, 1000)

		// Corrections
		FaceInterpCDS(mesh, pPrime, pFace)
		applyBCFaceValues(mesh, pPrime, pFace, ppBCs)
		GreenGaussGradient(mesh, pFace, gradPPrimeX, gradPPrimeY)

		for i := range Ux {
			Ux[i] -= (mesh.CellVolumes[i] / aPx[i]) * gradPPrimeX[i]
			Uy[i] -= (mesh.CellVolumes[i] / aPy[i]) * gradPPrimeY[i]
			p[i] += alphaP * pPrime[i]
		}

		if needsPressureRef {
			subtractMean(p)
		}

		// Update pressure gradient for next iteration
		FaceInterpCDS(mesh, p, pFace)
		applyBCFaceValues(mesh, p, pFace, pBCs)
		GreenGaussGradient(mesh, pFace, gradPx, gradPy)

		contRes := normL1(divU) * rho
		return contRes
	}

	return
}

//
// Helpers
//

func normL1(field []float64) float64 {
	var sum float64
	for _, v := range field {
		sum += math.Abs(v)
	}
	return sum
}

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

func hasDirichletBC(bcs []BC) bool {
	for _, bc := range bcs {
		if bc.Type == Dirichlet {
			return true
		}
	}
	return false
}

func subtractMean(field []float64) {
	var sum float64
	for _, v := range field {
		sum += v
	}
	mean := sum / float64(len(field))
	for i := range field {
		field[i] -= mean
	}
}
