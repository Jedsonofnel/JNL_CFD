package fvm

import (
	"slices"

	"jedn.dev/jnlcfd/geometry"
)

//
// Laplacian operator — arithmetic mean face interpolation
//

func LaplacianConst(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma float64,
	gradX, gradY []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		fluxCoeff := gamma * faceArea * orthFactor / distance
		matrix.lower[i] -= fluxCoeff
		matrix.upper[i] -= fluxCoeff

		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += fluxCoeff
			matrix.diag[conn.Neighbour] += fluxCoeff

			if hasCorrection {
				w := mesh.InterpWeights[i]
				gradXFace := (1-w)*gradX[conn.Owner] + w*gradX[conn.Neighbour]
				gradYFace := (1-w)*gradY[conn.Owner] + w*gradY[conn.Neighbour]
				delta := mesh.NonOrthDeltas[i]
				correction := gamma * faceArea * (delta.X*gradXFace + delta.Y*gradYFace)
				sys.Rhs[conn.Owner] += correction
				sys.Rhs[conn.Neighbour] -= correction
			}
		}
	}

	return nil
}

func LaplacianField(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma []float64,
	gradX, gradY []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		gammaOwner := gamma[conn.Owner]
		gammaFace := gammaOwner

		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			gammaFace = (1-w)*gammaOwner + w*gamma[conn.Neighbour]
		}

		fluxCoeff := gammaFace * faceArea * orthFactor / distance
		matrix.lower[i] -= fluxCoeff
		matrix.upper[i] -= fluxCoeff

		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += fluxCoeff
			matrix.diag[conn.Neighbour] += fluxCoeff

			if hasCorrection {
				w := mesh.InterpWeights[i]
				gradXFace := (1-w)*gradX[conn.Owner] + w*gradX[conn.Neighbour]
				gradYFace := (1-w)*gradY[conn.Owner] + w*gradY[conn.Neighbour]
				delta := mesh.NonOrthDeltas[i]
				correction := gammaFace * faceArea * (delta.X*gradXFace + delta.Y*gradYFace)
				sys.Rhs[conn.Owner] += correction
				sys.Rhs[conn.Neighbour] -= correction
			}
		}
	}
	return nil
}

func LaplacianExpr(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma Expression,
	gradX, gradY []float64,
	regionNames ...string,
) error {
	if gamma.IsConst {
		return LaplacianConst(sys, mesh, gamma.Eval(0), gradX, gradY, regionNames...)
	}

	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		gO := gamma.Eval(int(conn.Owner))
		gF := gO

		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			gF = (1-w)*gO + w*gamma.Eval(int(conn.Neighbour))
		}

		coeff := gF * faceArea * orthFactor / distance
		matrix.lower[i] -= coeff
		matrix.upper[i] -= coeff

		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += coeff
			matrix.diag[conn.Neighbour] += coeff

			if hasCorrection {
				w := mesh.InterpWeights[i]
				gradXFace := (1-w)*gradX[conn.Owner] + w*gradX[conn.Neighbour]
				gradYFace := (1-w)*gradY[conn.Owner] + w*gradY[conn.Neighbour]
				delta := mesh.NonOrthDeltas[i]
				correction := gF * faceArea * (delta.X*gradXFace + delta.Y*gradYFace)
				sys.Rhs[conn.Owner] += correction
				sys.Rhs[conn.Neighbour] -= correction
			}
		}
	}

	return nil
}

//
// Laplacian operator — harmonic mean face interpolation
//
// Use at material interfaces where gamma is discontinuous (e.g. steel→air).
// Arithmetic mean gives (50 + 0.026)/2 ≈ 25, harmonic gives ≈ 0.052.
// The harmonic mean correctly reflects that flux is limited by the
// resistive side: 1/γf = (1-w)/γO + w/γN.
//

func harmonicMean(gammaO, gammaN, w float64) float64 {
	denom := (1-w)/gammaO + w/gammaN
	if denom < 1e-30 {
		return 0
	}
	return 1.0 / denom
}

func LaplacianFieldHarmonic(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma []float64,
	gradX, gradY []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		gammaFace := gamma[conn.Owner]
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			gammaFace = harmonicMean(gamma[conn.Owner], gamma[conn.Neighbour], w)
		}

		fluxCoeff := gammaFace * faceArea * orthFactor / distance
		matrix.lower[i] -= fluxCoeff
		matrix.upper[i] -= fluxCoeff

		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += fluxCoeff
			matrix.diag[conn.Neighbour] += fluxCoeff

			if hasCorrection {
				w := mesh.InterpWeights[i]
				gradXFace := (1-w)*gradX[conn.Owner] + w*gradX[conn.Neighbour]
				gradYFace := (1-w)*gradY[conn.Owner] + w*gradY[conn.Neighbour]
				delta := mesh.NonOrthDeltas[i]
				correction := gammaFace * faceArea * (delta.X*gradXFace + delta.Y*gradYFace)
				sys.Rhs[conn.Owner] += correction
				sys.Rhs[conn.Neighbour] -= correction
			}
		}
	}
	return nil
}

func LaplacianExprHarmonic(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma Expression,
	gradX, gradY []float64,
	regionNames ...string,
) error {
	if gamma.IsConst {
		return LaplacianConst(sys, mesh, gamma.Eval(0), gradX, gradY, regionNames...)
	}

	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		gO := gamma.Eval(int(conn.Owner))
		gF := gO
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			gF = harmonicMean(gO, gamma.Eval(int(conn.Neighbour)), w)
		}

		coeff := gF * faceArea * orthFactor / distance
		matrix.lower[i] -= coeff
		matrix.upper[i] -= coeff

		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += coeff
			matrix.diag[conn.Neighbour] += coeff

			if hasCorrection {
				w := mesh.InterpWeights[i]
				gradXFace := (1-w)*gradX[conn.Owner] + w*gradX[conn.Neighbour]
				gradYFace := (1-w)*gradY[conn.Owner] + w*gradY[conn.Neighbour]
				delta := mesh.NonOrthDeltas[i]
				correction := gF * faceArea * (delta.X*gradXFace + delta.Y*gradYFace)
				sys.Rhs[conn.Owner] += correction
				sys.Rhs[conn.Neighbour] -= correction
			}
		}
	}
	return nil
}

//
// Divergence operator (implicit) — CDS interpolation
//

func DivConstCDS(
	sys *FVSystem,
	mesh *geometry.Mesh,
	rho float64,
	uNormal []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	for i, conn := range mesh.Connections {
		F := rho * uNormal[i] * mesh.FaceAreas[i]

		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			matrix.lower[i] -= F * (1 - w)
			matrix.upper[i] += F * w
			matrix.diag[conn.Owner] += F * (1 - w)
			matrix.diag[conn.Neighbour] -= F * w
		} else {
			matrix.upper[i] += F
		}
	}
	return nil
}

func DivFieldCDS(
	sys *FVSystem,
	mesh *geometry.Mesh,
	rho []float64,
	uNormal []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	for i, conn := range mesh.Connections {
		rhoOwner := rho[conn.Owner]
		rhoFace := rhoOwner
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			rhoFace = (1-w)*rhoOwner + w*rho[conn.Neighbour]
		}

		F := rhoFace * uNormal[i] * mesh.FaceAreas[i]

		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			matrix.lower[i] -= F * (1 - w)
			matrix.upper[i] += F * w
			matrix.diag[conn.Owner] += F * (1 - w)
			matrix.diag[conn.Neighbour] -= F * w
		} else {
			matrix.upper[i] += F
		}
	}
	return nil
}

func DivExprCDS(
	sys *FVSystem,
	mesh *geometry.Mesh,
	rho Expression,
	uNormal []float64,
	regionNames ...string,
) error {
	if rho.IsConst {
		return DivConstCDS(sys, mesh, rho.Eval(0), uNormal, regionNames...)
	}
	matrix := sys.Matrix
	for i, conn := range mesh.Connections {
		rhoOwner := rho.Eval(int(conn.Owner))
		rhoFace := rhoOwner
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			rhoFace = (1-w)*rhoOwner + w*rho.Eval(int(conn.Neighbour))
		}
		F := rhoFace * uNormal[i] * mesh.FaceAreas[i]
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			matrix.lower[i] -= F * (1 - w)
			matrix.upper[i] += F * w
			matrix.diag[conn.Owner] += F * (1 - w)
			matrix.diag[conn.Neighbour] -= F * w
		} else {
			matrix.upper[i] += F
		}
	}
	return nil
}

//
// Divergence operator (implicit) — UDS interpolation
//

func DivConstUDS(
	sys *FVSystem,
	mesh *geometry.Mesh,
	rho float64,
	uNormal []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	for i, conn := range mesh.Connections {
		F := rho * uNormal[i] * mesh.FaceAreas[i]

		if conn.Neighbour >= 0 {
			matrix.lower[i] -= max(F, 0)
			matrix.upper[i] -= max(-F, 0)
			matrix.diag[conn.Owner] += max(F, 0)
			matrix.diag[conn.Neighbour] += max(-F, 0)
		} else {
			matrix.upper[i] += F
		}
	}
	return nil
}

func DivFieldUDS(
	sys *FVSystem,
	mesh *geometry.Mesh,
	rho []float64,
	uNormal []float64,
	regionNames ...string,
) error {
	matrix := sys.Matrix
	for i, conn := range mesh.Connections {
		rhoOwner := rho[conn.Owner]
		rhoFace := rhoOwner
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			rhoFace = (1-w)*rhoOwner + w*rho[conn.Neighbour]
		}

		F := rhoFace * uNormal[i] * mesh.FaceAreas[i]

		if conn.Neighbour >= 0 {
			matrix.lower[i] -= max(F, 0)
			matrix.upper[i] -= max(-F, 0)
			matrix.diag[conn.Owner] += max(F, 0)
			matrix.diag[conn.Neighbour] += max(-F, 0)
		} else {
			matrix.upper[i] += F
		}
	}
	return nil
}

func DivExprUDS(
	sys *FVSystem,
	mesh *geometry.Mesh,
	rho Expression,
	uNormal []float64,
	regionNames ...string,
) error {
	if rho.IsConst {
		return DivConstUDS(sys, mesh, rho.Eval(0), uNormal, regionNames...)
	}
	matrix := sys.Matrix
	for i, conn := range mesh.Connections {
		rhoOwner := rho.Eval(int(conn.Owner))
		rhoFace := rhoOwner
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			rhoFace = (1-w)*rhoOwner + w*rho.Eval(int(conn.Neighbour))
		}
		F := rhoFace * uNormal[i] * mesh.FaceAreas[i]
		if conn.Neighbour >= 0 {
			matrix.lower[i] -= max(F, 0)
			matrix.upper[i] -= max(-F, 0)
			matrix.diag[conn.Owner] += max(F, 0)
			matrix.diag[conn.Neighbour] += max(-F, 0)
		} else {
			matrix.upper[i] += F
		}
	}
	return nil
}

//
// Source term S_u — adds to RHS, multiplied by cell volume
//

func SuConst(sys *FVSystem, mesh *geometry.Mesh, coeff float64, regionNames ...string) {
	mask := RegionsFromNames(mesh, regionNames...)
	for i := range sys.Rhs {
		if mask.Contains(mesh.CellRegions[i]) {
			sys.Rhs[i] += coeff * mesh.CellVolumes[i]
		}
	}
}

func SuField(sys *FVSystem, mesh *geometry.Mesh, field []float64, regionNames ...string) {
	mask := RegionsFromNames(mesh, regionNames...)
	for i := range sys.Rhs {
		if mask.Contains(mesh.CellRegions[i]) {
			sys.Rhs[i] += field[i] * mesh.CellVolumes[i]
		}
	}
}

func SuExpr(sys *FVSystem, mesh *geometry.Mesh, expr Expression, regionNames ...string) {
	if expr.IsConst && len(regionNames) == 0 {
		SuConst(sys, mesh, expr.Eval(0))
		return
	}
	mask := RegionsFromNames(mesh, regionNames...)
	for i := range sys.Rhs {
		if mask.Contains(mesh.CellRegions[i]) {
			sys.Rhs[i] += expr.Eval(i) * mesh.CellVolumes[i]
		}
	}
}

func SuIntegrated(sys *FVSystem, field []float64) {
	for i := range sys.Rhs {
		sys.Rhs[i] += field[i]
	}
}

func SuFieldScaled(sys *FVSystem, coeff float64, field []float64) {
	for i := range sys.Rhs {
		sys.Rhs[i] += coeff * field[i]
	}
}

//
// Explicit divergence source — integral form direct to RHS
//

func SuDivergenceConst(sys *FVSystem, mesh *geometry.Mesh, rho float64, UnFace []float64) {
	for i, conn := range mesh.Connections {
		flux := rho * UnFace[i] * mesh.FaceAreas[i]
		sys.Rhs[conn.Owner] += flux
		if conn.Neighbour >= 0 {
			sys.Rhs[conn.Neighbour] -= flux
		}
	}
}

func SuDivergenceField(sys *FVSystem, mesh *geometry.Mesh, rho []float64, UnFace []float64) {
	for i, conn := range mesh.Connections {
		rhoOwner := rho[conn.Owner]
		rhoFace := rhoOwner
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			rhoFace = (1-w)*rhoOwner + w*rho[conn.Neighbour]
		}
		flux := rhoFace * UnFace[i] * mesh.FaceAreas[i]
		sys.Rhs[conn.Owner] += flux
		if conn.Neighbour >= 0 {
			sys.Rhs[conn.Neighbour] -= flux
		}
	}
}

func SuDivergenceExpr(sys *FVSystem, mesh *geometry.Mesh, rho Expression, UnFace []float64) {
	if rho.IsConst {
		SuDivergenceConst(sys, mesh, rho.Eval(0), UnFace)
		return
	}
	for i, conn := range mesh.Connections {
		rhoOwner := rho.Eval(int(conn.Owner))
		rhoFace := rhoOwner
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			rhoFace = (1-w)*rhoOwner + w*rho.Eval(int(conn.Neighbour))
		}
		flux := rhoFace * UnFace[i] * mesh.FaceAreas[i]
		sys.Rhs[conn.Owner] += flux
		if conn.Neighbour >= 0 {
			sys.Rhs[conn.Neighbour] -= flux
		}
	}
}

//
// Source term S_p — adds to diagonal, multiplied by cell volume
//

func SpConst(sys *FVSystem, mesh *geometry.Mesh, coeff float64, regionNames ...string) {
	mask := RegionsFromNames(mesh, regionNames...)
	for i := range sys.Matrix.diag {
		if mask.Contains(mesh.CellRegions[i]) {
			sys.Matrix.diag[i] += coeff * mesh.CellVolumes[i]
		}
	}
}

func SpField(sys *FVSystem, mesh *geometry.Mesh, field []float64, regionNames ...string) {
	mask := RegionsFromNames(mesh, regionNames...)
	for i := range sys.Matrix.diag {
		if mask.Contains(mesh.CellRegions[i]) {
			sys.Matrix.diag[i] += field[i] * mesh.CellVolumes[i]
		}
	}
}

func SpExpr(sys *FVSystem, mesh *geometry.Mesh, expr Expression, regionNames ...string) {
	if expr.IsConst && len(regionNames) == 0 {
		SpConst(sys, mesh, expr.Eval(0))
		return
	}
	mask := RegionsFromNames(mesh, regionNames...)
	for i := range sys.Matrix.diag {
		if mask.Contains(mesh.CellRegions[i]) {
			sys.Matrix.diag[i] += expr.Eval(i) * mesh.CellVolumes[i]
		}
	}
}

func SpIntegrated(sys *FVSystem, field []float64) {
	for i := range sys.Matrix.diag {
		sys.Matrix.diag[i] += field[i]
	}
}

//
// Buoyancy (Boussinesq approximation)
//
// Returns -rho * beta * (T - Tref) * gComponent as volumetric source.
// Apply to Y-momentum for gravity, X-momentum if tilted.
//
//   SuExpr(UySys, mesh, BoussinesqExpr(1.2, 3.4e-3, 293, -9.81, FieldExpr(T)))
//

func BoussinesqExpr(rho, beta, Tref, gComponent float64, T Expression) Expression {
	coeff := -rho * beta * gComponent
	return Expression{
		Eval:    func(i int) float64 { return coeff * (T.Eval(i) - Tref) },
		IsConst: false,
	}
}

//
// Region masking and region helpers
//

type RegionMask map[int]bool

func (rm RegionMask) Contains(region int) bool {
	if rm == nil {
		return true
	}
	return rm[region]
}

func AllRegions() RegionMask {
	return nil
}

func RegionsFromNames(mesh *geometry.Mesh, names ...string) RegionMask {
	if len(names) == 0 {
		return nil
	}
	mask := make(RegionMask)
	for regionIdx, regionName := range mesh.RegionNames {
		if slices.Contains(names, regionName) {
			mask[regionIdx] = true
		}
	}
	return mask
}

// CellsInRegions returns all cell indices belonging to any of the named regions.
func CellsInRegions(mesh *geometry.Mesh, regionNames ...string) []int {
	mask := RegionsFromNames(mesh, regionNames...)
	if mask == nil {
		cells := make([]int, len(mesh.CellRegions))
		for i := range cells {
			cells[i] = i
		}
		return cells
	}
	var cells []int
	for i, r := range mesh.CellRegions {
		if mask[r] {
			cells = append(cells, i)
		}
	}
	return cells
}

// CellsNotInRegions returns the complement.
func CellsNotInRegions(mesh *geometry.Mesh, regionNames ...string) []int {
	mask := RegionsFromNames(mesh, regionNames...)
	if mask == nil {
		return nil
	}
	var cells []int
	for i, r := range mesh.CellRegions {
		if !mask[r] {
			cells = append(cells, i)
		}
	}
	return cells
}

// RegionExpr creates a per-cell expression that dispatches on region name.
//
//	k := RegionExpr(mesh, map[string]Expression{
//	    "solid": ConstExpr(50.0),
//	    "fluid": ConstExpr(0.026),
//	}, ConstExpr(1.0))
func RegionExpr(mesh *geometry.Mesh, exprs map[string]Expression, fallback Expression) Expression {
	idExprs := make(map[int]Expression, len(exprs))
	for name, expr := range exprs {
		for id, rname := range mesh.RegionNames {
			if rname == name {
				idExprs[id] = expr
			}
		}
	}
	return Expression{
		Eval: func(i int) float64 {
			if expr, ok := idExprs[mesh.CellRegions[i]]; ok {
				return expr.Eval(i)
			}
			return fallback.Eval(i)
		},
		IsConst: false,
	}
}
