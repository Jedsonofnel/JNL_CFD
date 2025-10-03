package jnlisp

import (
	"embed"
	"strconv"
)

//go:embed corelib.jnl
var coreLibFS embed.FS

func init() {
	RegisterLibrary(Library{
		Name: "core",
		FS:   coreLibFS,
		Bindings: map[string]ProcFunc{
			"+":   lispAdd,
			"-":   lispSubtract,
			"*":   lispMultiply,
			"/":   lispDivide,
			"%":   lispModulo,
			"=":   lispEqual,
			">":   lispGreaterThan,
			"not": lispNot,

			"vector-ref": lispVectorRef,
			"vector-length": lispVectorLength,
		},
		Atoms: map[string]Atom{},
	})
}

// STANDARD MATHS

func lispAdd(args []Atom, _ Table) (Atom, Error) {
	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.Value)
		} else {
			return nil, RuntimeError{Message: "+ expects numbers, got " + arg.Type()}
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

func lispSubtract(args []Atom, _ Table) (Atom, Error) {
	if len(args) == 0 {
		return nil, RuntimeError{Message: "- expects at least 1 argument"}
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.Value)
		} else {
			return nil, RuntimeError{Message: "- expects numbers, got " + arg.Type()}
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

func lispMultiply(args []Atom, _ Table) (Atom, Error) {
	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.Value)
		} else {
			return nil, RuntimeError{Message: "* expects numbers, got " + arg.Type()}
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

func lispDivide(args []Atom, _ Table) (Atom, Error) {
	if len(args) == 0 {
		return nil, RuntimeError{Message: "/ requires at least 1 argument"}
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.Value)
		} else {
			return nil, RuntimeError{Message: "/ expects numbers, got " + arg.Type()}
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

func lispModulo(args []Atom, _ Table) (Atom, Error) {
	if len(args) != 2 {
		return nil, RuntimeError{Message: "%% requires exactly 2 arguments"}
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.Value)
		} else {
			return nil, RuntimeError{Message: "%% expects numbers, got " + arg.Type()}
		}
	}

	arg1, ok1 := values[0].(int)
	arg2, ok2 := values[1].(int)
	if !ok1 || !ok2 {
		return nil, RuntimeError{Message: "%% expects integer arguments"}
	}

	return NumberAtom{arg1 % arg2}, nil
}

// BASIC COMPARATORS

func lispEqual(args []Atom, _ Table) (Atom, Error) {
	if len(args) < 2 {
		return nil, RuntimeError{
			Message: "= expects at least 2 arguments, got " + strconv.Itoa(len(args)),
		}
	}

	first := args[0]
	for i := 1; i < len(args); i++ {
		if !atomsEqual(first, args[i]) {
			return BooleanAtom{false}, nil
		}
	}

	return BooleanAtom{true}, nil
}

func lispGreaterThan(args []Atom, _ Table) (Atom, Error) {
	if len(args) != 2 {
		return nil, RuntimeError{
			Message: "> expects at least 2 arguments, got " + strconv.Itoa(len(args)),
		}
	}

	var values []any
	for _, arg := range args {
		if num, ok := As[NumberAtom](arg); ok {
			values = append(values, num.Value)
		} else {
			return nil, RuntimeError{Message: "> expects numbers, got " + arg.Type()}
		}
	}

	castArgs, err := toRational(values, ">")
	if err != nil {
		return nil, err
	}

	return BooleanAtom{castArgs[0] > castArgs[1]}, nil
}

func lispNot(args []Atom, _ Table) (Atom, Error) {
	if len(args) != 1 {
		return nil, RuntimeError{Message: "not expects at least 1 argument"}
	}

	boolean, ok := args[0].(BooleanAtom)
	if !ok {
		return nil, RuntimeError{Message: "not expects a boolean"}
	}

	return BooleanAtom{!boolean.Value}, nil
}

// VECTOR OPERATIONS

func lispVectorRef(args []Atom, kwargs Table) (Atom, Error) {
	vec, v := ValidateArgs(args, kwargs).GetVector()
	index, v := v.GetInt()

	v = v.ExpectNoMoreArgs()
	if err := v.Validate("vector-ref"); err != nil {
		return nil, err
	}

	if index < 0 || index >= len(vec.Elements) {
		return nil, RuntimeError{
			Message: "index out of bounds for vector",
		}
	}

	return vec.Elements[index], nil
}

func lispVectorLength(args []Atom, _ Table) (Atom, Error) {
	vec, v := ValidateArgs(args, nil).GetVector()
	v = v.ExpectNoMoreArgs()

	if err := v.Validate("vector-length"); err != nil {
		return nil, err
	}

	return NumberAtom{len(vec.Elements)}, nil
}

// HELPERS

func atomsEqual(a, b Atom) bool {
	if numA, okA := As[NumberAtom](a); okA {
		if numB, okB := As[NumberAtom](b); okB {
			values := []any{numA.Value, numB.Value}
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
		return va.Value == b.(BooleanAtom).Value
	case StringAtom:
		return va.Value == b.(StringAtom).Value
	default:
		return false
	}
}

func toRational(args []any, name string) ([]float64, Error) {
	cast := make([]float64, 0)

	for _, arg := range args {
		switch v := arg.(type) {
		case int:
			cast = append(cast, float64(v))
		case float32:
			cast = append(cast, float64(v))
		case float64:
			cast = append(cast, float64(v))
		default:
			return nil, RuntimeError{Message: name + " expects numbers"}
		}
	}

	return cast, nil
}

func toComplex(args []any, name string) ([]complex128, Error) {
	cast := make([]complex128, 0)

	for _, arg := range args {
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
			return nil, RuntimeError{Message: name + " expects numbers"}
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
