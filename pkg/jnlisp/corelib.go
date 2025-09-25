package jnlisp

import (
	"embed"
	"fmt"
)

//go:embed corelib.jnl
var coreLibSrc embed.FS

func init() {
	RegisterLibrary(Library{
		Name: "core",
		Src:  coreLibSrc,
		Bindings: map[string]ProcFunc{
			"+":   lispAdd,
			"-":   lispSubtract,
			"*":   lispMultiply,
			"/":   lispDivide,
			"%":   lispModulo,
			"=":   lispEqual,
			">":   lispGreaterThan,
			"not": lispNot,
		},
		Atoms: map[string]Atom{},
	})
}

// STANDARD MATHS

func lispAdd(args []Atom, _ table) (Atom, error) {
	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.value)
		} else {
			return nil, fmt.Errorf("+ expects numbers, got %s", arg.Type())
		}
	}

	castArgs, err := toComplex(values, "-")
	if err != nil {
		return nil, err
	}

	var result complex128 = 0
	for _, arg := range castArgs {
		result += arg
	}

	return simplifyNumber(result), nil
}

func lispSubtract(args []Atom, _ table) (Atom, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("- requires at least 1 argument")
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.value)
		} else {
			return nil, fmt.Errorf("- expects numbers, got %s", arg.Type())
		}
	}

	castArgs, err := toComplex(values, "-")
	if err != nil {
		return nil, err
	}

	if len(castArgs) == 1 {
		return simplifyNumber(-castArgs[0]), nil
	}

	var result complex128 = castArgs[0]
	for i := 1; i < len(castArgs); i++ {
		result -= castArgs[i]
	}

	return simplifyNumber(result), nil
}

func lispMultiply(args []Atom, _ table) (Atom, error) {
	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.value)
		} else {
			return nil, fmt.Errorf("/ expects numbers, got %s", arg.Type())
		}
	}

	castArgs, err := toComplex(values, "*")
	if err != nil {
		return nil, err
	}

	var result complex128 = 1
	for _, arg := range castArgs {
		result *= arg
	}

	return simplifyNumber(result), nil
}

func lispDivide(args []Atom, _ table) (Atom, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("/ requires at least 1 argument")
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.value)
		} else {
			return nil, fmt.Errorf("/ expects numbers, got %s", arg.Type())
		}
	}

	castArgs, err := toComplex(values, "/")
	if err != nil {
		return nil, err
	}

	if len(castArgs) == 1 {
		return simplifyNumber(1 / castArgs[0]), nil
	}

	var result complex128 = castArgs[0]
	for i := 1; i < len(castArgs); i++ {
		result /= castArgs[i]
	}

	return simplifyNumber(result), nil
}

func lispModulo(args []Atom, _ table) (Atom, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("%% requires exactly 2 arguments")
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.value)
		} else {
			return nil, fmt.Errorf("%% expects numbers, got %s", arg.Type())
		}
	}

	arg1, ok := values[0].(int)
	if !ok {
		return nil, fmt.Errorf("%% expects integers, got %T at position 0", args[0])
	}

	arg2, ok := values[1].(int)
	if !ok {
		return nil, fmt.Errorf("%% expects integers, got %T at position 1", args[1])
	}

	return NumberAtom{arg1 % arg2}, nil
}

// BASIC COMPARATORS

func lispEqual(args []Atom, _ table) (Atom, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("= expects at least 2 arguments, got %d", len(args))
	}

	first := args[0]
	for i := 1; i < len(args); i++ {
		if !atomsEqual(first, args[i]) {
			return BooleanAtom{false}, nil
		}
	}

	return BooleanAtom{true}, nil
}

func lispGreaterThan(args []Atom, _ table) (Atom, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("> expects exactly 2 arguments, got %d", len(args))
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.value)
		} else {
			return nil, fmt.Errorf("> expects numbers, got %s", arg.Type())
		}
	}

	castArgs, err := toRational(values, ">")
	if err != nil {
		return nil, err
	}

	return BooleanAtom{castArgs[0] > castArgs[1]}, nil
}

func lispNot(args []Atom, _ table) (Atom, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("not expects at least 1 argument, got %d", len(args))
	}

	boolean, ok := args[0].(BooleanAtom)
	if !ok {
		return nil, fmt.Errorf("not expects a boolean, got %s", args[0].Type())
	}

	return BooleanAtom{!boolean.value}, nil
}

// HELPERS

func atomsEqual(a, b Atom) bool {
	if numA, okA := As[NumberAtom](a); okA {
		if numB, okB := As[NumberAtom](b); okB {
			values := []any{numA.value, numB.value}
			castArgs, _ := toComplex(values, "")
			return castArgs[0] == castArgs[1]
		}
		return false // they are different types
	}

	if a.Type() != b.Type() {
		return false
	}

	switch va := a.(type) {
	case BooleanAtom:
		return va.value == b.(BooleanAtom).value
	case StringAtom:
		return va.value == b.(StringAtom).value
	default:
		return false
	}
}

func toRational(args []any, name string) ([]float64, error) {
	cast := make([]float64, 0)

	for i, arg := range args {
		switch v := arg.(type) {
		case int:
			cast = append(cast, float64(v))
		case float32:
			cast = append(cast, float64(v))
		case float64:
			cast = append(cast, float64(v))
		default:
			return nil, fmt.Errorf("%s expects numbers, got %T at position %d", name, arg, i)
		}
	}

	return cast, nil
}

func toComplex(args []any, name string) ([]complex128, error) {
	cast := make([]complex128, 0)

	for i, arg := range args {
		switch v := arg.(type) {
		case int:
			cast = append(cast, complex(float64(v), 0))
		case float32:
			cast = append(cast, complex(float64(v), 0))
		case float64:
			cast = append(cast, complex(float64(v), 0))
		case complex128:
			cast = append(cast, v)
		default:
			return nil, fmt.Errorf("%s expects numbers, got %T at position %d", name, arg, i)
		}
	}

	return cast, nil
}

func simplifyNumber(c complex128) Atom {
	if imag(c) == 0 {
		realPart := real(c)
		if realPart == float64(int(realPart)) {
			return NumberAtom{int(realPart)} // Return int if whole number
		}
		return NumberAtom{realPart} // Return float64
	}
	return NumberAtom{c} // Return complex128
}
