package fvm

import (
	"slices"

	"jedn.dev/jnlcfd/geometry"
)

//
// Core operators for equations
//

func LaplacianConstant(
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

// OLDER VERSION TO BE REPLACED!!!!
// func SourceConstant(
// 	sys *LinearSystem,
// 	ctx jnl.Map,
// 	value float64,
// 	regionNames ...string,
// ) error {
// 	mesh, err := GetMesh(ctx)
// 	if err != nil {
// 		return err
// 	}
//
// 	mask := RegionsFromNames(mesh, regionNames...)
//
// 	sys.ForEachCell(func(localIdx, globalIdx int) {
// 		if !mask.Contains(mesh.CellRegions[globalIdx]) {
// 			return
// 		}
// 		cellVolume := mesh.CellVolumes[globalIdx]
// 		sys.Source[localIdx] += value * cellVolume
// 	})
//
// 	return nil
// }

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
