package fvm

import (
	"slices"

	"jedn.dev/jnlcfd/geometry"
)

//
// Laplacian operator - for diffusion.  Comes in Const, Field and Expr variants
//

func LaplacianConst(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma float64,
	gradX, gradY []float64, // for non-orthogonality correction
	regionNames ...string,
) error {
	// mask := RegionsFromNames(mesh, regionNames...)
	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		// implicit coefficient orth-corrected
		fluxCoeff := gamma * faceArea * orthFactor / distance
		matrix.lower[i] -= fluxCoeff
		matrix.upper[i] -= fluxCoeff

		// add diagonals for internal connections
		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += fluxCoeff
			matrix.diag[conn.Neighbour] += fluxCoeff

			// explicit non-orthogonal correction
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
	matrix := sys.Matrix
	hasCorrection := len(gradX) > 0 && len(gradY) > 0

	if gamma.IsConst {
		return LaplacianConst(sys, mesh, gamma.Eval(0), gradX, gradY, regionNames...)
	}

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		orthFactor := mesh.OrthFactors[i]

		gO := gamma.Eval(int(conn.Owner))
		gF := gO

		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			gN := gamma.Eval(int(conn.Neighbour))
			gF = (1-w)*gO + w*gN
		}

		coeff := gF * faceArea * orthFactor / distance

		matrix.lower[i] -= coeff
		matrix.upper[i] -= coeff

		// add diagonals for internal connections
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
// Divergence operator (implicit) with CDS interpolation for const/field/expr
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
			rhoNeigh := rho.Eval(int(conn.Neighbour))
			rhoFace = (1-w)*rhoOwner + w*rhoNeigh
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
// Divergence operator (implicit) with UDS interpolation for const/field/expr
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
			rhoNeigh := rho.Eval(int(conn.Neighbour))
			rhoFace = (1-w)*rhoOwner + w*rhoNeigh
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
// Constant source (S_u) adds to rhs, by default multiplies by cell volume
//

func SuConst(sys *FVSystem, mesh *geometry.Mesh, coeff float64) {
	for i := range sys.Rhs {
		sys.Rhs[i] += coeff * mesh.CellVolumes[i]
	}
}

func SuField(sys *FVSystem, mesh *geometry.Mesh, field []float64) {
	for i := range sys.Rhs {
		sys.Rhs[i] += field[i] * mesh.CellVolumes[i]
	}
}

func SuExpr(sys *FVSystem, mesh *geometry.Mesh, expr Expression) {
	if expr.IsConst {
		SuConst(sys, mesh, expr.Eval(0))
		return
	}

	for i := range sys.Rhs {
		sys.Rhs[i] += expr.Eval(i) * mesh.CellVolumes[i]
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
// explicit divergence source - integral form direct to RHS
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
// Linear source (S_p) adds to diagonal, by default mulitiplies by cell volume
//

func SpConst(sys *FVSystem, mesh *geometry.Mesh, coeff float64) {
	for i := range sys.Matrix.diag {
		sys.Matrix.diag[i] += coeff * mesh.CellVolumes[i]
	}
}

func SpField(sys *FVSystem, mesh *geometry.Mesh, field []float64) {
	for i := range sys.Matrix.diag {
		sys.Matrix.diag[i] += field[i] * mesh.CellVolumes[i]
	}
}

func SpExpr(sys *FVSystem, mesh *geometry.Mesh, expr Expression) {
	if expr.IsConst {
		SpConst(sys, mesh, expr.Eval(0))
		return
	}

	for i := range sys.Matrix.diag {
		sys.Matrix.diag[i] += expr.Eval(i) * mesh.CellVolumes[i]
	}
}

func SpIntegrated(sys *FVSystem, field []float64) {
	for i := range sys.Matrix.diag {
		sys.Matrix.diag[i] += field[i]
	}
}

//
// Region masking
//

// Region mask masks an operator by region
type RegionMask map[int]bool

func (rm RegionMask) Contains(region int) bool {
	if rm == nil {
		return true
	}
	return rm[region]
}

// Helper constructors
func AllRegions() RegionMask {
	return nil // nil map = all regions
}

func RegionsFromNames(mesh *geometry.Mesh, names ...string) RegionMask {
	if len(names) == 0 {
		return nil // all regions
	}

	mask := make(RegionMask)
	for regionIdx, regionName := range mesh.RegionNames {
		if slices.Contains(names, regionName) {
			mask[regionIdx] = true
		}
	}
	return mask
}
