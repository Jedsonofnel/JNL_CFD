package field

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

type fluxOperatorType int

const (
	laplacianType fluxOperatorType = iota
	divType
)

type scalarFluxOperator struct {
	opType         fluxOperatorType
	coeff          float32
	coupledScalars []scalar
	precalcs       []float32
	fluxes         []float32
}

type scalarFluxOperatorProcedure func(
	op *scalarFluxOperator, mesh *geometry.Mesh, sys *systemAssemblyContext)

var fluxOpProcedureTable = [...]scalarFluxOperatorProcedure{
	scalarLaplacianProcedure,
}

func applyFluxes(op *scalarFluxOperator, mesh *geometry.Mesh, sys *systemAssemblyContext) {
	fluxOpProcedureTable[op.opType](op, mesh, sys)
}

func scalarLaplacianProcedure(
	op *scalarFluxOperator, mesh *geometry.Mesh, sys *systemAssemblyContext) {
	for i := range op.fluxes {
		op.fluxes[i] = op.precalcs[i]
	}

	for _, field := range op.coupledScalars {
		faceVals := field.getFaceValues()

		for i := range op.fluxes {
			op.fluxes[i] *= faceVals[i]
		}
	}

	mesh.ForEachInternal(func(i, j, f int) {
		flux := op.fluxes[f]
		sys.MatrixInternal.AddDiagonal(i, flux)
		sys.MatrixInternal.Subtract(i, j, flux)
	})

	mesh.ForEachBoundary(func(i, bIdx, f int) {
		flux := op.fluxes[f]
		sys.BoundaryDiag[bIdx] += flux
		sys.BoundaryOffDiag[bIdx] += flux
	})
}

// DEFINITIONS

type scalarLaplacianDefinition struct {
	coeff          float32
	coupledScalars []scalarDefinition
	error          error
}

func NewScalarLaplacian(owner *ScalarPrognosticDefinition, coeffs ...any) *scalarLaplacianDefinition {
	var coeff float32 = 1
	coupledScalars := make([]scalarDefinition, 0)
	var error error = nil

	for _, c := range coeffs {
		switch field := c.(type) {
		case float32:
			coeff *= field
		case int:
			coeff *= float32(field)
		case float64:
			coeff *= float32(field)
		case scalarDefinition:
			coupledScalars = append(coupledScalars, field)
		default:
			error = fmt.Errorf("NewScalarLaplacian > Cannot treat '%T' as a coefficient",
				field)

		}
	}

	return &scalarLaplacianDefinition{coeff, coupledScalars, error}
}

func (sld *scalarLaplacianDefinition) Resolve(mesh *geometry.Mesh) *scalarFluxOperator {
	precalcs := make([]float32, mesh.NumNeighbours())
	fluxes := make([]float32, mesh.NumNeighbours())

	for i := range mesh.NumNeighbours() {
		precalcs[i] = sld.coeff * mesh.FaceAreas[i] / mesh.ConnectionDistances[i]
	}

	coupledScalars := make([]scalar, len(sld.coupledScalars))
	for i, def := range sld.coupledScalars {
		coupledScalars[i] = def.follow()
	}

	return &scalarFluxOperator{
		opType:         laplacianType,
		coeff:          sld.coeff,
		coupledScalars: coupledScalars,
		precalcs:       precalcs,
		fluxes:         fluxes,
	}
}
