package fvm

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type bcType int

const (
	dirichlet bcType = iota
	neumann
	outflow
)

// INTERFACES

type BCDefinition interface {
	resolve(mesh *geometry.Mesh, boundaryName string) bc
	rank() rank
}

type bc interface {
	rank() rank
}

// DEFINITIONS

type ScalarDirichlet struct{ Value float32 }

func (sd ScalarDirichlet) resolve(mesh *geometry.Mesh, boundaryName string) bc {
	cellIndices, boundaryIndices := findBCIndices(mesh, boundaryName)

	return &scalarBC{
		bcType: dirichlet,
		value:  sd.Value,

		cellIndices:     cellIndices,
		boundaryIndices: boundaryIndices,
	}
}

func (sd ScalarDirichlet) rank() rank { return scalar }

type ScalarNeumann struct{ Flux float32 }

func (sn ScalarNeumann) resolve(mesh *geometry.Mesh, boundaryName string) bc {
	cellIndices, boundaryIndices := findBCIndices(mesh, boundaryName)

	return &scalarBC{
		bcType: neumann,
		value:  sn.Flux,

		cellIndices:     cellIndices,
		boundaryIndices: boundaryIndices,
	}
}

func (sn ScalarNeumann) rank() rank { return scalar }

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

// RESOLVED

type scalarBC struct {
	bcType bcType
	value  float32

	cellIndices     []int // what cell it acts on
	boundaryIndices []int // where to find the values
}

func (bc *scalarBC) rank() rank { return scalar }

type scalarBCProcedure func(
	bc *scalarBC,
	owner *scalarField,
	matrix *linalg.CSR,
	boundaryDiag, boundaryOffDiag, rhs []float32,
)

var scalarBCProcedureTable = [...]scalarBCProcedure{
	scalarDirichletProcedure,
	scalarNeumannProcedure,
	scalarOutflowProcedure,
}

func scalarDirichletProcedure(
	bc *scalarBC, _ *scalarField, matrix *linalg.CSR, bDiag, bOffDiag, rhs []float32) {
	for i, cellIdx := range bc.cellIndices {
		boundIdx := bc.boundaryIndices[i]
		matrix.AddDiagonal(cellIdx, bDiag[boundIdx])
		rhs[cellIdx] += bc.value * bOffDiag[boundIdx]
	}
}

func scalarNeumannProcedure(
	bc *scalarBC, _ *scalarField, _ *linalg.CSR, _, _, rhs []float32) {
	for _, cellIdx := range bc.cellIndices {
		rhs[cellIdx] += bc.value
	}
}

func scalarOutflowProcedure(_ *scalarBC, _ *scalarField, _ *linalg.CSR, _, _, _ []float32) {}
