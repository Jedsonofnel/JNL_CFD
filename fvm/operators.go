package fvm

import (
	"slices"

	"jedn.dev/jnlcfd/geometry"
)

//
// Core operators for equations
//

func LaplacianConst(
	sys *FVSystem,
	mesh *geometry.Mesh,
	gamma float64,
	regionNames ...string,
) error {
	// mask := RegionsFromNames(mesh, regionNames...)
	matrix := sys.Matrix

	for i, conn := range mesh.Connections {
		faceArea := mesh.FaceAreas[i]
		distance := mesh.ConnectionDists[i]
		fluxCoeff := gamma * faceArea / distance

		matrix.lower[i] -= fluxCoeff
		matrix.upper[i] -= fluxCoeff

		// add diagonals for internal connections
		if conn.Neighbour >= 0 {
			matrix.diag[conn.Owner] += fluxCoeff
			matrix.diag[conn.Neighbour] += fluxCoeff
		}
	}

	return nil
}

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

func SuConst(sys *FVSystem, mesh *geometry.Mesh, coeff float64) {
	for i := range sys.Rhs {
		sys.Rhs[i] += coeff * mesh.CellVolumes[i]
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
