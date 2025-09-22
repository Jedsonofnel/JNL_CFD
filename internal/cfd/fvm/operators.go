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
	linearSrc
)

var opTypeStrings = [...]string{
	"Laplacian",
	"Div",
	"DDT",
	"Grad",
	"Point Source",
	"Unifrom Source",
}

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
	opType        opType
	coeff         float32
	coupledFields []FieldDefinition
	error         error
}

type scalarOperatorPrecalcProcedure func(
	mesh *geometry.Mesh, coeff float32) (precals, fluxes []float32)

func newScalarLaplacian(owner FieldDefinition, coeffs ...any) *scalarOperatorDefinition {
	newLaplacian, err := parseScalarCoeffs(coeffs...)
	newLaplacian.opType = laplacian
	newLaplacian.error = err
	return newLaplacian
}

func newScalarDDT(owner FieldDefinition, coeffs ...any) *scalarOperatorDefinition {
	newDDT, err := parseScalarCoeffs(coeffs...)
	newDDT.opType = ddt
	newDDT.error = err
	return newDDT
}

func newScalarDiv(owner FieldDefinition, coeffs ...any) *scalarOperatorDefinition {
	newDiv, err := parseScalarCoeffs(coeffs...)
	newDiv.opType = div
	newDiv.error = err
	return newDiv
}

func newScalarLinearSource(owner FieldDefinition, coeffs ...any) *scalarOperatorDefinition {
	newReaction, err := parseScalarCoeffs(coeffs...)
	newReaction.opType = linearSrc
	newReaction.error = err
	return newReaction
}

func parseScalarCoeffs(coeffs ...any) (*scalarOperatorDefinition, error) {
	var coeff float32 = 1
	coupledFields := make([]FieldDefinition, 0)

	for _, c := range coeffs {
		switch field := c.(type) {
		case float32:
			coeff *= field
		case int:
			coeff *= float32(field)
		case float64:
			coeff *= float32(field)
		case FieldDefinition:
			coupledFields = append(coupledFields, field)
		default:
			return nil,
				fmt.Errorf("parseScalarCoeffs > cannot parse type '%T' as scalar operator coeff",
					c)
		}
	}

	return &scalarOperatorDefinition{
		coeff: coeff, coupledFields: coupledFields}, nil
}

func (sod *scalarOperatorDefinition) Validate() error {
	if sod.error != nil {
		return sod.error
	}

	vectors, scalars := 0, 0
	for _, op := range sod.coupledFields {
		switch op.rank() {
		case scalar:
			scalars++
		case vector:
			vectors++
		}
	}

	if sod.opType == div && vectors != 1 {
		return fmt.Errorf("scalarOperatorDefinition Validate > Div operator must have exactly one vector term.")
	}

	if sod.opType != div && vectors != 0 {
		return fmt.Errorf("scalarOperatorDefinition Validate > %s scalar operator cannot have a vector term",
			opTypeStrings[sod.opType])
	}

	return nil
}

var scalarOperatorPrecalcsTable = [...]scalarOperatorPrecalcProcedure{
	scalarLaplacianPrecalcs,
	scalarDivPrecalcs,
	scalarDDTPrecalcs,
	nil,
	nil,
	scalarLinearSourcePrecalcs,
}

func (sod *scalarOperatorDefinition) resolve(mesh *geometry.Mesh,
	fields map[string]field) (operator, error) {
	if err := sod.Validate(); err != nil {
		return nil, fmt.Errorf("scalarLaplacianDefinition resolve error > %w", err)
	}

	precalcProc := scalarOperatorPrecalcsTable[sod.opType]
	precalcs, fluxes := precalcProc(mesh, sod.coeff)

	coupledScalars := make([]*scalarField, 0)
	var coupledVector *vectorField

	for i, def := range sod.coupledFields {
		resolved, found := fields[def.getName()]
		if !found {
			return nil, fmt.Errorf("scalarLaplacianDefinition resolve > could not find field '%s' in registry",
				def.getName())
		}

		switch field := resolved.(type) {
		case *scalarField:
			coupledScalars[i] = field
		case *vectorField:
			coupledVector = field
		default:
			return nil, fmt.Errorf("scalarLaplacianDefinition resolve > could not cast '%s' to a field type",
				def.getName())
		}
	}

	return &scalarOperator{
		opType:         sod.opType,
		coeff:          sod.coeff,
		coupledScalars: coupledScalars,
		coupledVector:  coupledVector,
		precalcs:       precalcs,
		fluxes:         fluxes,
	}, nil
}

func scalarLaplacianPrecalcs(mesh *geometry.Mesh, coeff float32) (precalcs, fluxes []float32) {
	fluxes = make([]float32, mesh.NumNeighbours())
	precalcs = make([]float32, mesh.NumNeighbours())
	for i := range mesh.NumNeighbours() {
		precalcs[i] = coeff * mesh.FaceAreas[i] / mesh.ConnectionDistances[i]
	}
	return
}

func scalarDivPrecalcs(mesh *geometry.Mesh, coeff float32) (precalcs, fluxes []float32) {
	fluxes = make([]float32, mesh.NumNeighbours())
	precalcs = make([]float32, mesh.NumNeighbours())
	for i := range mesh.NumNeighbours() {
		precalcs[i] = coeff * mesh.FaceAreas[i] // we are assuming face values for a vector will be normal to face
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

func scalarLinearSourcePrecalcs(mesh *geometry.Mesh, coeff float32) (precalcs, fluxes []float32) {
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
	switch owner.rank() {
	case scalar:
		return newScalarLaplacian(owner, coeffs...)
	}
	return nil
}

func NewDiv(owner FieldDefinition, coeffs ...any) OperatorDefinition {
	switch owner.rank() {
	case scalar:
		return newScalarDiv(owner, coeffs...)
	}
	return nil
}

func NewDDT(owner FieldDefinition, coeffs ...any) OperatorDefinition {
	switch owner.rank() {
	case scalar:
		return newScalarDDT(owner, coeffs...)
	}
	return nil
}

func NewScalarPointSource(handler *ScalarPointSourceHandler) OperatorDefinition {
	return &scalarPointSourceDefinition{handler}
}

func NewLinearSource(owner FieldDefinition, coeffs ...any) OperatorDefinition {
	switch owner.rank() {
	case scalar:
		return newScalarLinearSource(owner, coeffs...)
	}
	return nil
}

// RESOLVED

type scalarOperator struct {
	opType         opType
	coeff          float32
	coupledScalars []*scalarField
	coupledVector  *vectorField
	precalcs       []float32
	fluxes         []float32 // this is a misnomer for source operators

	// for point sources
	psHandler *ScalarPointSourceHandler
}

func (so *scalarOperator) rank() rank           { return scalar }
func (so *scalarOperator) operatorType() opType { return so.opType }

type scalarOpProcedure func(op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation)

var scalarOpProcedureTable = [...]scalarOpProcedure{
	scalarLaplacianProcedure,
	scalarDivProcedure,
	scalarDDTProcedure,
	nil, // GRAD
	scalarPointSrcProcedure,
	scalarLinearSrcProcedure,
}

func scalarLaplacianProcedure(op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	for i := range op.fluxes {
		op.fluxes[i] = op.precalcs[i]
	}

	mesh.ForEachConnection(func(i, j, f int) {
		flux := op.fluxes[f]
		if j >= 0 {
			eq.matrixInternal.AddDiagonal(i, flux)
			eq.matrixInternal.Subtract(i, j, flux)
		} else {
			bIdx := -j - 1
			eq.boundaryDiag[bIdx] += flux
			eq.boundaryOffDiag[bIdx] += flux
		}
	})
}

func scalarDivProcedure(op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	for i := range op.fluxes {
		op.fluxes[i] = op.precalcs[i] * op.coupledVector.faceValues[i]
	}

	// UPWIND: if flux < 0 (therefore flux is inwards) then face value is equal
	// to neighbour centroid and so the neighbour contributes "more"
	// a_n = MAX(-F_n, 0)
	// a_p = SUM(a_n) + SUM(F_n)
	mesh.ForEachConnection(func(i, j, f int) {
		flux := op.fluxes[f]
		if j >= 0 {
			eq.matrixInternal.AddDiagonal(i, flux)
			eq.matrixInternal.Subtract(i, j, max(-flux, 0))
		} else {
			bIdx := -j - 1 // eg -5 becomes -(-5)-1 = 4
			eq.boundaryDiag[bIdx] += flux
			eq.boundaryOffDiag[bIdx] += max(-flux, 0)
		}
	})
}

func scalarDDTProcedure(op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	for i := range op.fluxes {
		op.fluxes[i] = op.precalcs[i] / eq.dt
	}

	for i := range mesh.NumCells() {
		flux := op.fluxes[i]
		eq.matrix.AddDiagonal(i, flux)
		eq.rhs[i] += flux * eq.owner.cellValues0[i]
	}
}

func scalarPointSrcProcedure(op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	for i, src := range op.fluxes {
		eq.rhs[i] += src * eq.dt

		if src != 0 {
			fmt.Printf("Point source cell value: %.6f, RHS contribution: %.6f\n",
				eq.owner.cellValues[i], src*eq.dt)
		}
	}
}

func scalarLinearSrcProcedure(op *scalarOperator, mesh *geometry.Mesh, eq *scalarEquation) {
	if op.coeff > 0 {
		for i := range mesh.NumCells() {
			eq.rhs[i] += op.precalcs[i] * eq.owner.cellValues0[i]
		}
	} else {
		for i := range mesh.NumCells() {
			absCoeff := -op.precalcs[i]
			eq.matrix.AddDiagonal(i, absCoeff)
			// eq.rhs[i] += absCoeff * eq.owner.cellValues0[i]
		}
	}
}
