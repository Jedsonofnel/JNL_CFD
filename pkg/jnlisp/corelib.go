package jnlisp

import (
	"embed"
	"strconv"
)

//go:embed corelib.jnl
var coreLibFS embed.FS

var corePkg = Package{
	Name: "core",
	FS:   coreLibFS,
	Bindings: map[string]NativeFunction{
		"+":   SimpleNative(lispAdd),
		"-":   SimpleNative(lispSubtract),
		"*":   SimpleNative(lispMultiply),
		"/":   SimpleNative(lispDivide),
		"%":   SimpleNative(lispModulo),
		"=":   SimpleNative(lispEqual),
		">":   SimpleNative(lispGreaterThan),
		"not": SimpleNative(lispNot),

		"vector-ref":    SimpleNative(lispVectorRef),
		"vector-length": SimpleNative(lispVectorLength),
	},
	Sexps: map[string]Sexp{},
}

// STANDARD MATHS

func lispAdd(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	nums := v.GetVariadicComplex128()
	v.ExpectNoMoreArgs()
	if err := v.Validate("/"); err != nil {
		return nil, err
	}

	var result complex128 = 0
	for _, arg := range nums {
		result += arg
	}

	return simplifyNumber(result), nil
}

func lispSubtract(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	nums := v.GetVariadicComplex128()
	v.ExpectNoMoreArgs()
	if err := v.Validate("/"); err != nil {
		return nil, err
	}

	if len(nums) == 0 {
		return nil, RuntimeError{Message: "- expects at least 1 argument"}
	}

	if len(nums) == 1 {
		return simplifyNumber(-nums[0]), nil
	}

	var result complex128 = nums[0]
	for i := 1; i < len(nums); i++ {
		result -= nums[i]
	}

	return simplifyNumber(result), nil
}

func lispMultiply(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	nums := v.GetVariadicComplex128()
	v.ExpectNoMoreArgs()
	if err := v.Validate("/"); err != nil {
		return nil, err
	}

	var result complex128 = 1
	for _, arg := range nums {
		result *= arg
	}

	return simplifyNumber(result), nil
}

func lispDivide(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	nums := v.GetVariadicComplex128()
	v.ExpectNoMoreArgs()
	if err := v.Validate("/"); err != nil {
		return nil, err
	}

	if len(nums) == 0 {
		return nil, RuntimeError{Message: "/ requires at least 1 argument"}
	}

	if len(nums) == 1 {
		return simplifyNumber(1 / nums[0]), nil
	}

	var result complex128 = nums[0]
	for i := 1; i < len(nums); i++ {
		result /= nums[i]
	}

	return simplifyNumber(result), nil
}

func lispModulo(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	num1 := v.GetInt()
	num2 := v.GetInt()
	v.ExpectNoMoreArgs()
	if err := v.Validate("%%"); err != nil {
		return nil, err
	}

	return Int(num1 % num2), nil
}

// BASIC COMPARATORS

func lispEqual(args []Sexp, kwargs Map) (Sexp, Error) {
	if len(args) < 2 {
		return nil, RuntimeError{
			Message: "= expects at least 2 arguments, got " + strconv.Itoa(len(args)),
		}
	}

	first := args[0]
	for i := 1; i < len(args); i++ {
		if !sexpsEqual(first, args[i]) {
			return nil, nil
		}
	}

	return Boolean(true), nil
}

func lispGreaterThan(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	num1 := v.GetFloat64()
	num2 := v.GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate(">"); err != nil {
		return nil, err
	}

	return Boolean(num1 > num2), nil
}

func lispNot(args []Sexp, _ Map) (Sexp, Error) {
	if len(args) != 1 {
		return nil, RuntimeError{Message: "not expects at least 1 argument"}
	}

	boolean, ok := args[0].(Boolean)
	if !ok {
		return nil, RuntimeError{Message: "not expects a boolean"}
	}

	return !boolean, nil
}

// VECTOR OPERATIONS

func lispVectorRef(args []Sexp, kwargs Map) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	vec := v.GetVector()
	index := v.GetInt()

	v.ExpectNoMoreArgs()
	if err := v.Validate("vector-ref"); err != nil {
		return nil, err
	}

	if index < 0 || index >= len(vec) {
		return nil, RuntimeError{
			Message: "index out of bounds for vector",
		}
	}

	return vec[index], nil
}

func lispVectorLength(args []Sexp, _ Map) (Sexp, Error) {
	v := ValidateArgs(args, nil)
	vec := v.GetVector()
	v.ExpectNoMoreArgs()

	if err := v.Validate("vector-length"); err != nil {
		return nil, err
	}

	return Int(len(vec)), nil
}

// HELPERS

func sexpsEqual(a, b Sexp) bool {
	if numA, okA := a.(Number); okA {
		if numB, okB := b.(Number); okB {
			complexA := numA.ToComplex128()
			complexB := numB.ToComplex128()
			return complexA == complexB
		}
		return false // they are different types
	}

	if a.Type() != b.Type() {
		return false
	}

	switch va := a.(type) {
	case Boolean:
		return va == b.(Boolean)
	case String:
		return va == b.(String)
	case Keyword:
		return va == b.(Keyword)
	case Symbol:
		return va == b.(Symbol)
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

func simplifyNumber(c complex128) Sexp {
	if imag(c) == 0 {
		realPart := real(c)
		if realPart == float64(int(realPart)) {
			return Int(realPart) // Return int if whole number
		}
		return Float(realPart) // Return float64
	}
	return Complex(c) // Return complex128
}
