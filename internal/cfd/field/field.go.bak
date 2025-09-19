package field

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type TensorRank int

const (
	ScalarRank TensorRank = iota
	VectorRank
)

type FieldType int

const (
	UniformType FieldType = iota
	ConstantType
	TimeEvolvingType
	PrognosticType
)

type Field interface {
	GetName() string
	getType() FieldType
	getMesh() *geometry.Mesh
	getRank() TensorRank
}

type TimeEvolving interface {
	Field
	AdvanceTime(dt float32)
	SetTimestep(dt float32)
	getTimestep() float32
}

type Scalar interface {
	Field
	GetValues() []float32
	SetValues(newValues []float32)
	getFaceValues() []float32
}

type ScalarPrognostic interface {
	Scalar
	TimeEvolving
	AssembleSystem() *linalg.System
	getPastValues() []float32
}

//	type Vector interface {
//		Field
//		GetAllComponents() (x, y []float32)
//	}
//
// // Definitions
type FieldDefinition interface {
	Validate() error
	GetName() string

	getRank() TensorRank
	getType() FieldType
	follow() Field
}

type PrognosticDefinition interface {
	FieldDefinition
	SetEquation(...OperatorDefinition) error
}

type ScalarDefinition interface {
	FieldDefinition
	Resolve(mesh *geometry.Mesh) (Scalar, error)
}

type ScalarPrognosticDefinition interface {
	ScalarDefinition
	PrognosticDefinition
	ResolveAsPrognostic(mesh *geometry.Mesh) (ScalarPrognostic, error)
}

//
// SHARED UTILITY FUNCTIONS

func validateOperatorsForField(field PrognosticDefinition, operators []OperatorDefinition) error {
	if len(operators) == 0 {
		return fmt.Errorf("Validate Operators (%s) > Missing operators", field.GetName())
	}

	for _, op := range operators {
		if err := op.Validate(); err != nil {
			return fmt.Errorf("Validate Operators (%s) > %w", field.GetName(), err)
		}

		if flux, ok := op.(FluxOperatorDefinition); ok && !(flux.GetOwner() != field) {
			return fmt.Errorf("Validate Operators (%s) > Operator %T must be owned by %s but is owned by %s.",
				field.GetName(), op, field.GetName(), flux.GetOwner().GetName())
		}
	}

	return nil
}
