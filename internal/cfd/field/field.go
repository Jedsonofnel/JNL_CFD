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
	GetType() FieldType
	GetMesh() *geometry.Mesh
	GetRank() TensorRank
}

type TimeEvolving interface {
	Field
	AdvanceTime(dt float32)
	GetTimestep() float32
	SetTimestep(dt float32)
}

type Scalar interface {
	Field
	GetValues() []float32
	SetValues(newValues []float32)
	GetFaceValues() []float32
}

type ScalarTimeEvolving interface {
	Scalar
	TimeEvolving
	GetPastValues() []float32
}

type ScalarPrognostic interface {
	Scalar
	AssembleSystem() *linalg.System
}

type Vector interface {
	Field
	GetAllComponents() (x, y []float32)
}

// Definitions
type FieldDefinition interface {
	GetName() string
	GetRank() TensorRank
	GetType() FieldType
	Validate() error
	Follow() Field
}

type PrognosticDefinition interface {
	FieldDefinition
	SetEquation(...OperatorDefinition) error
}

type ScalarDefinition interface {
	FieldDefinition
	Resolve() (Scalar, error)
}

type ScalarPrognosticDefinition interface {
	ScalarDefinition
	PrognosticDefinition
}

// SHARED UTILITY FUNCTIONS

func validateOperatorsForField(field PrognosticDefinition, operators []OperatorDefinition) error {
	if len(operators) == 0 {
		return fmt.Errorf("Validate Operators (%s) > Missing operators", field.GetName())
	}

	for _, op := range operators {
		if err := op.Validate(); err != nil {
			return fmt.Errorf("Validate Operators (%s) > %w", err)
		}

		if flux, ok := op.(FluxOperatorDefinition); ok && !(flux.GetOwner() != field) {
			return fmt.Errorf("Validate Operators (%s) > Operator %T must be owned by %s but is owned by %s.",
				field.GetName(), op, field.GetName(), flux.GetOwner().GetName())
		}
	}

	return nil
}
