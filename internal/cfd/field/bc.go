package field

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type scalarBCType int

const (
	ScalarDirichletType scalarBCType = iota
	ScalarNeumannType
	ScalarOutflowType
)

type scalarBC struct {
	bcType scalarBCType
	value  float32

	cellIndices     []int // what cell it acts on
	boundaryIndices []int // where to find the values
}

type bcProcedure func(
	bc *scalarBC,
	owner *ScalarPrognostic,
	matrix *linalg.CSR,
	boundaryDiag, boundaryOffDiag, rhs []float32,
)

var scalarProcedureTable = [...]bcProcedure{
	scalarDirichletProcedure,
	scalarNeumannProcedure,
	scalarOutflowProcedure,
}

func applyScalarBC(bc *scalarBC, owner *ScalarPrognostic, sys *systemAssemblyContext) {
	scalarProcedureTable[bc.bcType](
		bc, owner, sys.Matrix, sys.BoundaryDiag, sys.BoundaryOffDiag, sys.RHS)
}

func scalarDirichletProcedure(
	bc *scalarBC, _ *ScalarPrognostic, matrix *linalg.CSR, bDiag, bOffDiag, rhs []float32) {
	for i, cellIdx := range bc.cellIndices {
		boundIdx := bc.boundaryIndices[i]
		matrix.AddDiagonal(cellIdx, bDiag[boundIdx])
		rhs[cellIdx] += bc.value * bOffDiag[boundIdx]
	}
}

func scalarNeumannProcedure(
	bc *scalarBC, _ *ScalarPrognostic, _ *linalg.CSR, _, _, rhs []float32) {
	for _, cellIdx := range bc.cellIndices {
		rhs[cellIdx] += bc.value
	}
}

func scalarOutflowProcedure(_ *scalarBC, _ *ScalarPrognostic, _ *linalg.CSR, _, _, _ []float32) {}

// DEFINITIONS

type ScalarBCDefinition interface {
	Resolve(mesh *geometry.Mesh, boundaryName string) *scalarBC
}

type ScalarDirichlet struct{ Value float32 }

func (sd ScalarDirichlet) Resolve(mesh *geometry.Mesh, boundaryName string) *scalarBC {
	cellIndices, boundaryIndices := findBCIndices(mesh, boundaryName)

	return &scalarBC{
		bcType: ScalarDirichletType,
		value:  sd.Value,

		cellIndices:     cellIndices,
		boundaryIndices: boundaryIndices,
	}
}

type ScalarNeumann struct{ Flux float32 }

func (sn ScalarNeumann) Resolve(mesh *geometry.Mesh, boundaryName string) *scalarBC {
	cellIndices, boundaryIndices := findBCIndices(mesh, boundaryName)

	return &scalarBC{
		bcType: ScalarNeumannType,
		value:  sn.Flux,

		cellIndices:     cellIndices,
		boundaryIndices: boundaryIndices,
	}
}

func findBCIndices(mesh *geometry.Mesh, boundaryName string) (cellIndices, boundaryIndices []int) {
	marker := -1
	for i, name := range mesh.Boundaries {
		if name == boundaryName {
			marker = i
		}
	}

	if marker == -1 {
		panic(fmt.Sprintf("Could not find '%s' boundary on mesh for field",
			boundaryName))
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
