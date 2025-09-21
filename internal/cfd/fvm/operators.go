package fvm

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

type opType int

const (
	laplacian opType = iota // 
	div                     // FLUXES END
	ddt                     // SOURCES START
	source                  // 
	grad
)

// INTERFACES

type OperatorDefinition interface {
	Validate() error
	resolve(mesh *geometry.Mesh, fields map[string]field) (operator, error)
	rank() rank
}

type operator interface {
	rank() rank
	operatorType() opType
}

// DEFINITIONS

type scalarLaplacianDefinition struct {
	coeff          float32
	coupledScalars []*scalarFieldDefinition
	error          error
}

func newScalarLaplacian(owner *scalarFieldDefinition, coeffs ...any) *scalarLaplacianDefinition {
	var coeff float32 = 1
	coupledScalars := make([]*scalarFieldDefinition, 0)
	var error error = nil

	for _, c := range coeffs {
		switch field := c.(type) {
		case float32:
			coeff *= field
		case int:
			coeff *= float32(field)
		case float64:
			coeff *= float32(field)
		case *scalarFieldDefinition:
			coupledScalars = append(coupledScalars, field)
		default:
			error = fmt.Errorf("NewScalarLaplacian > Cannot treat '%T' as a coefficient",
				field)

		}
	}

	return &scalarLaplacianDefinition{coeff, coupledScalars, error}
}

func (sld *scalarLaplacianDefinition) Validate() error {
	if sld.error != nil {
		return sld.error
	}
	return nil
}

func (sld *scalarLaplacianDefinition) resolve(mesh *geometry.Mesh,
	fields map[string]field) (operator, error) {
	if err := sld.Validate(); err != nil {
		return nil, fmt.Errorf("scalarLaplacianDefinition resolve error > %w", err)
	}

	precalcs := make([]float32, mesh.NumNeighbours())
	fluxes := make([]float32, mesh.NumNeighbours())

	for i := range mesh.NumNeighbours() {
		precalcs[i] = sld.coeff * mesh.FaceAreas[i] / mesh.ConnectionDistances[i]
	}

	coupledScalars := make([]*scalarField, len(sld.coupledScalars))

	for i, def := range sld.coupledScalars {
		resolved, found := fields[def.name]
		if !found {
			return nil, fmt.Errorf("scalarLaplacianDefinition resolve > could not find field '%s' in registry",
				def.name)
		}

		field, ok := resolved.(*scalarField)
		if !ok {
			return nil, fmt.Errorf("scalarLaplacianDefinition resolve > could not cast '%s' to *scalarField",
				def.name)
		}

		coupledScalars[i] = field
	}

	return &scalarOperator{
		opType:         laplacian,
		coeff:          sld.coeff,
		coupledScalars: coupledScalars,
		precalcs:       precalcs,
		fluxes:         fluxes,
	}, nil
}

func (sld *scalarLaplacianDefinition) rank() rank { return scalar }

// DEFINITION FACTORIES

func NewLaplacian(owner FieldDefinition, coeffs ...any) OperatorDefinition {
	switch owner := owner.(type) {
	case *scalarFieldDefinition:
		return newScalarLaplacian(owner, coeffs...)
	}
	return nil
}

// RESOLVED

type scalarOperator struct {
	opType         opType
	coeff          float32
	coupledScalars []*scalarField
	precalcs       []float32
	fluxes         []float32
}

func (so *scalarOperator) rank() rank           { return scalar }
func (so *scalarOperator) operatorType() opType { return so.opType }

type scalarOpProcedure func(
	op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation)

var scalarOpProcedureTable = [...]scalarOpProcedure{
	scalarLaplacianProcedure,
}

func scalarLaplacianProcedure(
	op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	for i := range op.fluxes {
		op.fluxes[i] = op.precalcs[i]
	}

	mesh.ForEachInternal(func(i, j, f int) {
		flux := op.fluxes[f]
		eq.matrixInternal.AddDiagonal(i, flux)
		eq.matrixInternal.Subtract(i, j, flux)
	})

	mesh.ForEachBoundary(func(i, bIdx, f int) {
		flux := op.fluxes[f]
		eq.boundaryDiag[bIdx] += flux
		eq.boundaryOffDiag[bIdx] += flux
	})
}
