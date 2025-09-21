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
	grad                    //
	pointSrc
	uniformSrc
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

type scalarOperatorDefinition struct {
	opType         opType
	coeff          float32
	coupledScalars []*scalarFieldDefinition
	error          error
}

type scalarOperatorPrecalcProcedure func(
	mesh *geometry.Mesh, coeff float32) (precals, fluxes []float32)

func newScalarLaplacian(owner *scalarFieldDefinition, coeffs ...any) *scalarOperatorDefinition {
	newLaplacian, err := parseScalarCoeffs(coeffs...)
	newLaplacian.opType = laplacian
	newLaplacian.error = err
	return newLaplacian
}

func newScalarDDT(owner *scalarFieldDefinition, coeffs ...any) *scalarOperatorDefinition {
	newDDT, err := parseScalarCoeffs(coeffs...)
	newDDT.opType = ddt
	newDDT.error = err
	return newDDT
}

func parseScalarCoeffs(coeffs ...any) (*scalarOperatorDefinition, error) {
	var coeff float32 = 1
	coupledScalars := make([]*scalarFieldDefinition, 0)

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
			return nil,
				fmt.Errorf("parseScalarCoeffs > cannot parse type '%T' as scalar operator coeff",
					c)
		}
	}

	return &scalarOperatorDefinition{
		coeff: coeff, coupledScalars: coupledScalars}, nil
}

func (sod *scalarOperatorDefinition) Validate() error {
	return sod.error
}

var scalarOperatorPrecalcsTable = [...]scalarOperatorPrecalcProcedure{
	scalarLaplacianPrecalcs,
	nil,
	scalarDDTPrecalcs,
}

func (sod *scalarOperatorDefinition) resolve(mesh *geometry.Mesh,
	fields map[string]field) (operator, error) {
	if err := sod.Validate(); err != nil {
		return nil, fmt.Errorf("scalarLaplacianDefinition resolve error > %w", err)
	}

	precalcProc := scalarOperatorPrecalcsTable[sod.opType]
	precalcs, fluxes := precalcProc(mesh, sod.coeff)

	coupledScalars := make([]*scalarField, len(sod.coupledScalars))

	for i, def := range sod.coupledScalars {
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
		opType:         sod.opType,
		coeff:          sod.coeff,
		coupledScalars: coupledScalars,
		precalcs:       precalcs,
		fluxes:         fluxes,
	}, nil
}

func scalarLaplacianPrecalcs(mesh *geometry.Mesh, coeff float32,
) (precalcs, fluxes []float32) {
	fluxes = make([]float32, mesh.NumNeighbours())
	precalcs = make([]float32, mesh.NumNeighbours())
	for i := range mesh.NumNeighbours() {
		precalcs[i] = coeff * mesh.FaceAreas[i] / mesh.ConnectionDistances[i]
	}
	return
}

func scalarDDTPrecalcs(mesh *geometry.Mesh, coeff float32) (precalcs, fluxes []float32) {
	fluxes = make([]float32, mesh.NumCells())
	precalcs = make([]float32, mesh.NumCells())
	for i := range mesh.NumCells() {
		precalcs[i] = coeff * mesh.CellVolumes[i]
	}
	return
}

func (sld *scalarOperatorDefinition) rank() rank { return scalar }

type scalarPointSourceDefinition struct {
	handler *ScalarPointSourceHandler
}

func (psd *scalarPointSourceDefinition) Validate() error {
	return nil
}

func (psd *scalarPointSourceDefinition) resolve(mesh *geometry.Mesh, _ map[string]field,
) (operator, error) {
	handler := psd.handler
	handler.mesh = mesh

	fluxes := make([]float32, mesh.NumCells())

	so := &scalarOperator{
		opType:    pointSrc,
		fluxes:    fluxes,
		psHandler: handler,
	}

	handler.operator = so

	for i, point := range handler.setupPoints {
		psd.handler.SetPointSource(point.X, point.Y, handler.setupValues[i])
	}

	return so, nil
}

func (psd *scalarPointSourceDefinition) rank() rank { return scalar }

// DEFINITION FACTORIES

func NewLaplacian(owner FieldDefinition, coeffs ...any) OperatorDefinition {
	switch owner := owner.(type) {
	case *scalarFieldDefinition:
		return newScalarLaplacian(owner, coeffs...)
	}
	return nil
}

func NewDDT(owner FieldDefinition, coeffs ...any) OperatorDefinition {
	switch owner := owner.(type) {
	case *scalarFieldDefinition:
		return newScalarDDT(owner, coeffs...)
	}
	return nil
}

func NewScalarPointSource(handler *ScalarPointSourceHandler) OperatorDefinition {
	return &scalarPointSourceDefinition{handler}
}

// RESOLVED

type scalarOperator struct {
	opType         opType
	coeff          float32
	coupledScalars []*scalarField
	precalcs       []float32
	fluxes         []float32 // this is a misnomer for source operators

	// for point sources
	psHandler *ScalarPointSourceHandler
}

func (so *scalarOperator) rank() rank           { return scalar }
func (so *scalarOperator) operatorType() opType { return so.opType }

type scalarOpProcedure func(
	op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation)

var scalarOpProcedureTable = [...]scalarOpProcedure{
	scalarLaplacianProcedure,
	nil, // DIV
	scalarDDTProcedure,
	nil, // GRAD
	scalarPointSrcProcedure,
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

func scalarDDTProcedure(
	op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {

	for i := range op.fluxes {
		op.fluxes[i] = op.precalcs[i] / eq.dt
	}

	for i := range mesh.NumCells() {
		flux := op.fluxes[i]
		eq.matrix.AddDiagonal(i, flux)
		eq.rhs[i] += flux * eq.owner.cellValues0[i]
	}
}

func scalarPointSrcProcedure(
	op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	for i, src := range op.fluxes {
		eq.rhs[i] += src
	}
}
