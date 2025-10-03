package jnlisp

import (
	"strings"
)

// ATOMS (eval turns expressions into Atom)

type Atom interface {
	String() string
	Type() string
	ToJSON() string
}

type NumberAtom struct{ Value any }

// TODO: get number atom String() to work better
func (n NumberAtom) Type() string   { return "number" }
func (n NumberAtom) String() string { return "NUMBER" }
func (n NumberAtom) ToJSON() string { return "JSON PENDING" }

func (n NumberAtom) ToFloat64() (float64, error) {
	switch v := n.Value.(type) {
	case float64:
		return v, nil
	case float32:
		return float64(v), nil
	case int:
		return float64(v), nil
	default:
		return 0, RuntimeError{Message: "cannot convert to float64"}
	}
}

type BooleanAtom struct{ Value bool }

func (b BooleanAtom) Type() string { return "boolean" }
func (b BooleanAtom) String() string {
	if b.Value {
		return "#t"
	} else {
		return "#f"
	}
}
func (b BooleanAtom) ToJSON() string { return "JSON PENDING" }

type StringAtom struct{ Value string }

func (s StringAtom) Type() string   { return "string" }
func (s StringAtom) String() string { return s.Value }
func (s StringAtom) ToJSON() string { return "JSON PENDING" }

type ProcedureAtom struct{ *Procedure }

func (p ProcedureAtom) Type() string { return "procedure" }
func (p ProcedureAtom) String() string {
	// TODO: maybe add a pretty print of params
	return "#<procedure:" + p.name + ">"
}
func (p ProcedureAtom) ToJSON() string { return "JSON PENDING" }

type VectorAtom struct{ Elements []Atom }

func (v VectorAtom) Type() string { return "vector" }
func (v VectorAtom) String() string {
	var parts []string
	for _, elem := range v.Elements {
		parts = append(parts, elem.String())
	}
	return "[" + strings.Join(parts, " ") + "]"
}
func (v VectorAtom) ToJSON() string { return "JSON PENDING" }

func (v VectorAtom) Length() int {
	return len(v.Elements)
}

// WRAPPER TYPE FOR QUERYING ENV

type boundAtom struct {
	Atom
	handle string
	env    *env
}

func (b boundAtom) ToJSON() string {
	return b.Atom.ToJSON()
}

func (b boundAtom) Type() string   { return b.Atom.Type() }
func (b boundAtom) String() string { return b.Atom.String() }

func As[T Atom](atom Atom) (T, bool) {
	var zero T
	atom = UnwrapAtom(atom)

	if result, ok := (atom).(T); ok {
		return result, true
	}

	return zero, false
}

func UnwrapAtom(atom Atom) Atom {
	if boundAtom, ok := atom.(boundAtom); ok {
		return boundAtom.Atom
	}
	return atom
}
