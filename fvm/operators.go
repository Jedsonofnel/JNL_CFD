package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/geometry"
	jnl "jedn.dev/jnlisp"
)

//
// Core operators for equations
//

func LaplacianConstant(
	sys *LinearSystem,
	ctx jnl.Map,
	gammaKey string,
	regionNames ...string,
) error {
	mesh, err := GetMesh(ctx)
	if err != nil {
		return err
	}

	gamma, err := GetFieldExpression(ctx, gammaKey)
	if err != nil {
		return err
	}

	mask := RegionsFromNames(mesh, regionNames...)

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

	return nil
}

func SourceConstant(
	sys *LinearSystem,
	ctx jnl.Map,
	value float64,
	regionNames ...string,
) error {
	mesh, err := GetMesh(ctx)
	if err != nil {
		return err
	}

	mask := RegionsFromNames(mesh, regionNames...)

	sys.ForEachCell(func(localIdx, globalIdx int) {
		if !mask.Contains(mesh.CellRegions[globalIdx]) {
			return
		}
		cellVolume := mesh.CellVolumes[globalIdx]
		sys.Source[localIdx] += value * cellVolume
	})

	return nil
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
		for _, name := range names {
			if regionName == name {
				mask[regionIdx] = true
				break
			}
		}
	}
	return mask
}
