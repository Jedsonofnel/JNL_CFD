package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

func init() {
	jnlisp.RegisterLibrary(jnlisp.Library{
		Name: "cfd/fvm",
		Bindings: map[string]jnlisp.ProcFunc{
			"prognostic-scalar-field": lispPrognosticScalarField,
		},
		Atoms: map[string]jnlisp.Atom{},
	})
}

// FIELDS

type FieldDefinitionAtom struct{ value FieldDefinition }

func (fd FieldDefinitionAtom) Type() string {
	switch r := fd.value.rank(); r {
	case scalar:
		return "cfd/fvm.FieldDefinition (scalar)"
	case vector:
		return "cfd/fvm.FieldDefinition (vector)"
	default:
		return "cfd/fvm.FieldDefinition"
	}
}

func (fd FieldDefinitionAtom) String() string {
	name := fd.value.getName()
	switch r := fd.value.rank(); r {
	case scalar:
		return "cfd/fvm.FieldDefinition (scalar): " + name
	case vector:
		return "cfd/fvm.FieldDefinition (vector): " + name
	default:
		return "cfd/fvm.FieldDefinition " + name
	}
}

func (fd FieldDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  fd.Type(),
		"value": "INTERFACE TYPE",
		"repr":  fd.String(),
	}
}

func lispPrognosticScalarField(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	name, v := jnlisp.ValidateArgs(args, kwargs).GetString()
	v.ExpectNoMoreArgs()
	initialValue, v := v.GetKeywordFloat32("initial-value")

	if err := v.Validate(); err != nil {
		return nil, err
	}

	fd := NewPrognosticScalarField(name, initialValue)
	return FieldDefinitionAtom{fd}, nil
}

// func lispDerivedVectorField(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
// 	name, validator := jnlisp.ValidateArgs(args, kwargs).GetString()
// 	validator.ExpectNoMoreArgs()
//
// 	if err := validator.Validate(); err != nil {
// 		return nil, err
// 	}
//
// 	vf := NewDerivedVectorField(name, func(t float32) Vec2 {
// 		return initialValue
// 	})
//
// 	return FieldDefinitionAtom{vf}, nil
// }
