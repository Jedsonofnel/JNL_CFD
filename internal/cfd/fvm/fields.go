package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

type rank int

const (
	scalar rank = iota
	vector
)

type FieldDefinition interface {
	Validate() error
	resolve(mesh *geometry.Mesh) (field, error)
	rank() rank
}

type field interface {
	rank() rank
}

// DEFINITIONS

type scalarFieldDefinition struct {
	name         string
	initialValue float32
}

func NewPrognosticScalarField(name string, initialValue float32,
) *scalarFieldDefinition {
	return &scalarFieldDefinition{
		name:         name,
		initialValue: initialValue,
	}
}

func (sfd *scalarFieldDefinition) Validate() error {
	return nil
}

func (sfd *scalarFieldDefinition) resolve(mesh *geometry.Mesh,
) (field, error) {
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
		cellValues:  cellValues,
		cellValues0: cellValues0,
	}, nil
}

func (sfd *scalarFieldDefinition) rank() rank { return scalar }

// RESOLVED

type scalarField struct {
	name string

	cellValues  []float32
	cellValues0 []float32
}

func (sf *scalarField) rank() rank { return scalar }

// PERF: not every scalar field will vary in time - could be a function lookup
// to allow for fieldType based behaviour (eg constants would do nothing)
func (sf *scalarField) advanceTime() {
	copy(sf.cellValues0, sf.cellValues)
}
