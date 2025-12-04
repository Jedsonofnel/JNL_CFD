package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/geometry"
	jnl "jedn.dev/jnlisp"
)

//
// Core operators for equations
//

func LaplacianConstant(
	eq *Equation,
	ctx jnl.Map,
	gammaKey string,
	mask RegionMask,
) (*Equation, error) {
	meshVal := ctx.Lookup(jnl.NewKeyword("mesh"))
	mesh := meshVal.(*geometry.Mesh)

	gamma, err := GetExpression(ctx, gammaKey)
	if err != nil {
		return nil, err
	}

	eq.ForEachConnection(func(localIdx, globalIdx, owner, neighbour int) {
		if !mask.Contains(mesh.CellRegions[owner]) {
			return // skip this connection
		}

		// get local indices
		localOwner := eq.GetLocalCellIndex(owner)
		localNeighbour := eq.GetLocalCellIndex(neighbour)

		gammaFace := gamma.Eval(owner)
		geomDiff := gammaFace * mesh.FaceAreas[globalIdx] / mesh.ConnectionDists[globalIdx]

		// write to local arrays
		eq.Diag[localOwner] += geomDiff
		eq.Diag[localNeighbour] += geomDiff
		eq.UpperDiag[localIdx] -= geomDiff
		eq.LowerDiag[localIdx] -= geomDiff
	})

	eq.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if !mask.Contains(mesh.CellRegions[owner]) {
			return
		}

		gammaFace := gamma.Eval(owner)
		geomDiff := gammaFace * mesh.FaceAreas[globalIdx] /
			mesh.ConnectionDists[globalIdx]

		eq.AddBoundaryFlux(boundaryIdx, geomDiff, geomDiff)
	})

	return eq, nil
}

// LinearSourceOperator is a generalised linear source S_u + S_p * phi
// Linearized as S_u contributes to source, S_p contributes to diag
func LinearSourceOperator(
	eq *Equation,
	ctx *Context,
	phiName string,
	Su *Expression, // explicit source
	Sp *Expression, // implicit coefficient (negative for stability)
	mask RegionMask,
) *Equation {
	mesh := ctx.Mesh

	eq.ForEachCell(func(localIdx, globalIdx int) {
		if !mask.Contains(mesh.CellRegions[globalIdx]) {
			return
		}

		vol := mesh.CellVolumes[globalIdx]

		if Su != nil {
			eq.Source[localIdx] += Su.Eval(globalIdx) * vol
		}

		if Sp != nil {
			eq.Diag[localIdx] -= Sp.Eval(globalIdx) * vol // Note: Sp should be negative for stability
		}
	})

	return eq
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

func RegionsFromNames(ctx *Context, names ...string) RegionMask {
	if len(names) == 0 {
		return nil
	}

	mask := make(RegionMask)
	for regionIdx, regionName := range ctx.Regions {
		for _, name := range names {
			if regionName == name {
				mask[regionIdx] = true
				break
			}
		}
	}
	return mask
}
