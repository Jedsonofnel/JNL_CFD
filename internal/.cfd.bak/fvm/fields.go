package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type Vec2 linalg.Vec2

type rank int

const (
	scalar rank = iota
	vector
)

type fieldType int

const (
	constant fieldType = iota
	derived
	governed
)

type FieldDefinition interface {
	Validate() error
	resolve(mesh *geometry.Mesh) (field, error)
	rank() rank
	getName() string
}

type field interface {
	rank() rank
}

// DEFINITIONS

// DEFINITIONS > SCALARS

type scalarFieldDefinition struct {
	name         string
	initialValue float32
}

func NewPrognosticScalarField(name string, initialValue float32) *scalarFieldDefinition {
	return &scalarFieldDefinition{
		name:         name,
		initialValue: initialValue,
	}
}

func (sfd *scalarFieldDefinition) Validate() error {
	return nil
}

func (sfd *scalarFieldDefinition) resolve(mesh *geometry.Mesh) (field, error) {
	if err := sfd.Validate(); err != nil {
		return &scalarField{}, nil
	}

	cellValues := make([]float32, mesh.NumCells())
	cellValues0 := make([]float32, mesh.NumCells())

	for i := range mesh.NumCells() {
		cellValues[i] = sfd.initialValue
		cellValues0[i] = sfd.initialValue
	}

	return &scalarField{
		name:        sfd.name,
		fieldType:   governed,
		cellValues:  cellValues,
		cellValues0: cellValues0,
	}, nil
}

func (sfd *scalarFieldDefinition) rank() rank { return scalar }

func (sfd *scalarFieldDefinition) getName() string { return sfd.name }

// DEFINITION > VECTORS

type vectorDerivationProc func(t float32) Vec2

type derivedVectorFieldDefinition struct {
	name           string
	derivationProc vectorDerivationProc
}

func NewDerivedVectorField(name string, proc vectorDerivationProc) FieldDefinition {
	return &derivedVectorFieldDefinition{name, proc}
}

func (vf *derivedVectorFieldDefinition) Validate() error {
	return nil
}

func (vf *derivedVectorFieldDefinition) resolve(mesh *geometry.Mesh) (field, error) {
	cellValues := make([]Vec2, mesh.NumCells())
	startingVal := vf.derivationProc(0)
	for i := range cellValues {
		cellValues[i] = startingVal
	}

	faceValues := make([]float32, mesh.NumNeighbours())
	for i := range faceValues {
		faceValues[i] = startingVal.X*mesh.FaceNormals[i].X + startingVal.Y*mesh.FaceNormals[i].Y
	}

	return &vectorField{
		fieldType:      derived,
		name:           vf.name,
		cellValues:     cellValues,
		faceValues:     faceValues,
		derivationProc: vf.derivationProc,
	}, nil
}

func (vf *derivedVectorFieldDefinition) rank() rank { return vector }

func (vf *derivedVectorFieldDefinition) getName() string { return vf.name }

// RESOLVED

// RESOLVED > SCALARS

type scalarField struct {
	fieldType fieldType
	name      string

	cellValues  []float32
	cellValues0 []float32
}

func (sf *scalarField) rank() rank { return scalar }

func derivedScalarAdvanceTime(sf *scalarField, t float32) {
	// TODO:  figure this out when I get a use case
}

func governedScalarAdvanceTime(sf *scalarField) {
	copy(sf.cellValues0, sf.cellValues)
}

// RESOLVED > VECTORS

type vectorField struct {
	fieldType fieldType
	name      string

	cellValues  []Vec2
	cellValues0 []Vec2
	faceValues  []float32 // Ie normal to face (outwards)

	derivationProc vectorDerivationProc
}

func (vf *vectorField) rank() rank { return vector }

func derivedVectorAdvanceTime(vf *vectorField, t float32, faceNormals []geometry.Vec2) {
	newVal := vf.derivationProc(t)
	for i := range vf.cellValues {
		vf.cellValues[i] = newVal
	}

	for i := range vf.faceValues {
		vf.faceValues[i] = newVal.X*faceNormals[i].X + newVal.Y*faceNormals[i].Y
	}
}
