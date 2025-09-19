package field

import (
	"fmt"
)

type scalarBCType int

const (
	ScalarDirichletType scalarBCType = iota
	ScalarNeumannType
	ScalarOutflowType
)

type scalarBC struct {
	bcType scalarBCType
	owner  *ScalarPrognostic
	value  float32

	cellIndices     []int // what cell it acts on
	boundaryIndices []int // where to find the values
}

type bcProcedure func(bc *scalarBC, sys *systemAssemblyContext)

var scalarProcedureTable = [...]bcProcedure{
	scalarDirichletProcedure,
	scalarNeumannProcedure,
	scalarOutflowProcedure,
}

func applyScalarBC(bc *scalarBC, sys *systemAssemblyContext) {
	scalarProcedureTable[bc.bcType](bc, sys)
}

func scalarDirichletProcedure(bc *scalarBC, sys *systemAssemblyContext) {
	for i, cellIdx := range bc.cellIndices {
		boundIdx := bc.boundaryIndices[i]
		sys.Matrix.AddDiagonal(cellIdx, sys.BoundaryDiag[boundIdx])
		sys.RHS[cellIdx] += bc.value * sys.BoundaryOffDiag[boundIdx]
	}
}

func scalarNeumannProcedure(bc *scalarBC, sys *systemAssemblyContext) {
	for _, cellIdx := range bc.cellIndices {
		sys.RHS[cellIdx] += bc.value
	}
}

func scalarOutflowProcedure(bc *scalarBC, sys *systemAssemblyContext) {}

// DEFINITIONS

type ScalarBCDefinition interface {
	Resolve(owner *ScalarPrognostic, boundaryName string) *scalarBC
}

type ScalarDirichlet struct{ Value float32 }

func (sd ScalarDirichlet) Resolve(owner *ScalarPrognostic, boundaryName string) *scalarBC {
	cellIndices, boundaryIndices := findBCIndices(owner, boundaryName)

	return &scalarBC{
		bcType: ScalarDirichletType,
		owner:  owner,
		value:  sd.Value,

		cellIndices:     cellIndices,
		boundaryIndices: boundaryIndices,
	}
}

type ScalarNeumann struct{ Flux float32 }

func (sn ScalarNeumann) Resolve(owner *ScalarPrognostic, boundaryName string) *scalarBC {
	cellIndices, boundaryIndices := findBCIndices(owner, boundaryName)

	return &scalarBC{
		bcType: ScalarNeumannType,
		owner:  owner,
		value:  sn.Flux,

		cellIndices:     cellIndices,
		boundaryIndices: boundaryIndices,
	}
}

func findBCIndices(owner *ScalarPrognostic, boundaryName string) (cellIndices, boundaryIndices []int) {
	mesh := owner.mesh
	marker := -1
	for i, name := range mesh.Boundaries {
		if name == boundaryName {
			marker = i
		}
	}

	if marker == -1 {
		panic(fmt.Sprintf("Could not find '%s' boundary on mesh for field '%s'",
			boundaryName, owner.name))
	}

	cellIndices = make([]int, 0)
	boundaryIndices = make([]int, 0)

	mesh.ForEachBoundary(func(cellIdx, boundIdx, faceIdx int) {
		if mesh.FaceMarkers[faceIdx] == marker {
			cellIndices = append(cellIndices, cellIdx)
			boundaryIndices = append(boundaryIndices, boundIdx)
		}
	})

	return
}
