package jnlisp

import (
	"strconv"
	"strings"
)

// ATOMS (eval turns expressions into Atom)

type Atom interface {
	String() string
	Type() string
}

func CastAtom[T Atom](atom Atom) (T, bool) {
	var zero T

	if result, ok := (atom).(T); ok {
		return result, true
	}

	return zero, false
}

// LITERAL ATOM TYPES

type NumberAtom struct{ Value any }

func (n NumberAtom) Type() string { return "number" }
func (n NumberAtom) String() string {
	switch v := n.Value.(type) {
	case int:
		return strconv.Itoa(v)
	case float32:
		return strconv.FormatFloat(float64(v), 'g', -1, 32)
	case float64:
		return strconv.FormatFloat(v, 'g', -1, 64)
	case complex128:
		return strconv.FormatComplex(v, 'g', -1, 128)
	default:
		return "UNKNOWN NUMBER TYPE"
	}
}

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

type StringAtom struct{ Value string }

func (s StringAtom) Type() string   { return "string" }
func (s StringAtom) String() string { return s.Value }

type ProcedureAtom struct{ *Procedure }

func (p ProcedureAtom) Type() string { return "procedure" }
func (p ProcedureAtom) String() string {
	// TODO: maybe add a pretty print of params
	return "#<procedure:" + p.name + ">"
}

// COMPOUND DATA TYPES

type VectorAtom struct{ Elements []Atom }

func (v VectorAtom) Type() string { return "vector" }
func (v VectorAtom) String() string {
	var parts []string
	for _, elem := range v.Elements {
		parts = append(parts, elem.String())
	}
	return "[" + strings.Join(parts, " ") + "]"
}

func (v VectorAtom) Length() int {
	return len(v.Elements)
}

type TableAtom struct{ Elements map[string]Atom }

func (t TableAtom) Type() string { return "table" }
func (t TableAtom) String() string {
	var parts []string
	for k, v := range t.Elements {
		parts = append(parts, ":"+k+" "+v.String())
	}
	return "{" + strings.Join(parts, " ") + "}"
}

// HOMOICONIC DATA TYPES

type SymbolAtom struct{ Name string }

func (s SymbolAtom) Type() string   { return "symbol" }
func (s SymbolAtom) String() string { return s.Name }

type ListAtom struct{ Elements []Atom }

func (l ListAtom) Type() string { return "list" }
func (l ListAtom) String() string {
	var parts []string
	for _, elem := range l.Elements {
		parts = append(parts, elem.String())
	}
	return "(" + strings.Join(parts, " ") + ")"
}

// METAPROGRAMMING HELPERS

func atomToRaw(atom Atom) (any, Error) {
	switch a := atom.(type) {
	case SymbolAtom:
		return symbol(a.Name), nil
	case ListAtom:
		raw := make(listRaw, len(a.Elements))
		for i, elem := range a.Elements {
			r, err := atomToRaw(elem)
			if err != nil {
				return nil, err
			}
			raw[i] = r
		}
		return raw, nil
	case VectorAtom:
		raw := make(vectorRaw, len(a.Elements))
		for i, elem := range a.Elements {
			r, err := atomToRaw(elem)
			if err != nil {
				return nil, err
			}
			raw[i] = r
		}
		return raw, nil
	case TableAtom:
		raw := make(tableRaw, 0, len(a.Elements)*2)
		for k, v := range a.Elements {
			raw = append(raw, keyword(k))
			vraw, err := atomToRaw(v)
			if err != nil {
				return nil, err
			}
			raw = append(raw, vraw)
		}
		return raw, nil
	case NumberAtom:
		return a.Value, nil
	case BooleanAtom:
		return a.Value, nil
	case StringAtom:
		return a.Value, nil
	case ProcedureAtom:
		return nil, RuntimeError{
			Message: "cannot convert procedure to raw AST",
		}
	default:
		return nil, RuntimeError{
			Message: "cannot convert " + a.Type() + " to raw AST",
		}
	}
}
