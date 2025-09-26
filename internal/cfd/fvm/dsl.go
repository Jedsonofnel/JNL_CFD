package fvm

import (
	"fmt"

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

func lispDerivedVectorField(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	name, v := jnlisp.ValidateArgs(args, kwargs).GetString()
	timeFunc, v := v.GetProcedure()
	v = v.ExpectNoMoreArgs()

	if err := v.Validate(); err != nil {
		return nil, err
	}

	cb := func(t float32) Vec2 {
		timeAtom := jnlisp.NumberAtom{Value: t}
		result, err := timeFunc.Call([]jnlisp.Atom{timeAtom}, nil, nil)
		if err != nil {
			return Vec2{}
		}

		if vecAtom, ok := jnlisp.As[jnlisp.VectorAtom](result); ok {
			if vec2, err := lispVectorToVec2(vecAtom); err == nil {
				return vec2
			}
		}

		return Vec2{}
	}

	vf := NewDerivedVectorField(name, cb)
	return FieldDefinitionAtom{vf}, nil
}

// helper

func lispVectorToVec2(vec jnlisp.VectorAtom) (Vec2, error) {
	if vec.Length() != 2 {
		return Vec2{}, fmt.Errorf("Vec2 requires exactly 2 elements, got %d",
			vec.Length())
	}

	// Extract X component
	xAtom, ok := jnlisp.As[jnlisp.NumberAtom](vec.Elements[0])
	if !ok {
		return Vec2{}, fmt.Errorf("Vec2 element 0 (X): expected number, got %s",
			vec.Elements[0].Type())
	}

	x, err := xAtom.ToFloat64()
	if err != nil {
		return Vec2{}, fmt.Errorf("Vec2 element 0 (X): %w", err)
	}

	// Extract Y component
	yAtom, ok := jnlisp.As[jnlisp.NumberAtom](vec.Elements[1])
	if !ok {
		return Vec2{}, fmt.Errorf("Vec2 element 1 (Y): expected number, got %s",
			vec.Elements[1].Type())
	}

	y, err := yAtom.ToFloat64()
	if err != nil {
		return Vec2{}, fmt.Errorf("Vec2 element 1: %w", err)
	}

	return Vec2{X: float32(x), Y: float32(y)}, nil
}
