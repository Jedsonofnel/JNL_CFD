package fvm

import (
	jnl "jedn.dev/jnlisp"
)

//
// Core operators for equations
//

func LaplacianConstant(
	sys *LinearSystem,
	ctx jnl.Map,
	gammaKey string,
	mask RegionMask,
) (*LinearSystem, error) {
	mesh, err := GetMesh(ctx)
	if err != nil {
		return sys, err
	}

	gamma, err := GetFieldExpression(ctx, gammaKey)
	if err != nil {
		return nil, err
	}

	sys.ForEachConnection(func(localIdx, globalIdx, owner, neighbour int) {
		if !mask.Contains(mesh.CellRegions[owner]) {
			return // skip this connection
		}

		// get local indices
		localOwner := sys.GetLocalCellIndex(owner)
		localNeighbour := sys.GetLocalCellIndex(neighbour)

		gammaFace := gamma.Eval(owner)
		geomDiff := gammaFace * mesh.FaceAreas[globalIdx] / mesh.ConnectionDists[globalIdx]

		// write to local arrays
		sys.Diag[localOwner] += geomDiff
		sys.Diag[localNeighbour] += geomDiff
		sys.UpperDiag[localIdx] -= geomDiff
		sys.LowerDiag[localIdx] -= geomDiff
	})

	sys.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if !mask.Contains(mesh.CellRegions[owner]) {
			return
		}

		gammaFace := gamma.Eval(owner)
		geomDiff := gammaFace * mesh.FaceAreas[globalIdx] /
			mesh.ConnectionDists[globalIdx]

		sys.AddBoundaryFlux(boundaryIdx, geomDiff, geomDiff)
	})

	return sys, nil
}

func SourceConstant(sys *LinearSystem, value float64) {
	sys.ForEachCell(func(localIdx, globalIdx int) {
		sys.Source[localIdx] += value
	})
}

//
// Masking operators by region
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

func RegionsFromIndices(indices ...int) RegionMask {
	if len(indices) == 0 {
		return nil
	}

	mask := make(RegionMask)
	for _, idx := range indices {
		mask[idx] = true
	}
	return mask
}

// func RegionsFromNames(ctx *Context, names ...string) RegionMask {
// 	if len(names) == 0 {
// 		return nil
// 	}
//
// 	mask := make(RegionMask)
// 	for regionIdx, regionName := range ctx.Regions {
// 		for _, name := range names {
// 			if regionName == name {
// 				mask[regionIdx] = true
// 				break
// 			}
// 		}
// 	}
// 	return mask
// }
