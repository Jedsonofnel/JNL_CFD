package jnlisp

import (
	"fmt"
	"math"
)

type env map[symbol]any

func newStandardEnv() (env env) {
	env = make(map[symbol]any)

	defineProc := func(name string, fn LispFunc) {
		env[symbol(name)] = fn
	}

	// funci
	defineProc("+", lispAdd)
	defineProc("-", lispSubtract)
	defineProc("*", lispMultiply)
	defineProc("/", lispDivide)
	defineProc("%", lispModulo)
	defineProc("sin", lispSine)
	defineProc("cos", lispCosine)
	defineProc("sqrt", lispSqrt)

	return
}

type LispFunc func(args ...any) (any, error)

// STANDARD MATHS

func lispAdd(args ...any) (any, error) {
	castArgs, err := toComplex(args, "-")
	if err != nil {
		return nil, err
	}

	var result complex128 = 0
	for _, arg := range castArgs {
		result += arg
	}

	return simplifyNumber(result), nil
}

func lispSubtract(args ...any) (any, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("- requires at least 1 argument")
	}

	castArgs, err := toComplex(args, "-")
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

func lispMultiply(args ...any) (any, error) {
	castArgs, err := toComplex(args, "*")
	if err != nil {
		return nil, err
	}

	var result complex128 = 1
	for _, arg := range castArgs {
		result *= arg
	}

	return simplifyNumber(result), nil
}

func lispDivide(args ...any) (any, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("/ requires at least 1 argument")
	}

	castArgs, err := toComplex(args, "/")
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

func lispModulo(args ...any) (any, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("%% requires exactly 2 arguments")
	}

	arg1, ok := args[0].(int)
	if !ok {
		return nil, fmt.Errorf("%% expects integers, got %T at position 0", args[0])
	}

	arg2, ok := args[1].(int)
	if !ok {
		return nil, fmt.Errorf("%% expects integers, got %T at position 1", args[1])
	}

	return arg1 % arg2, nil
}

func lispSine(args ...any) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("sin requires exactly 1 argument")
	}

	castArgs, err := toRational(args, "sin")
	if err != nil {
		return nil, err
	}

	return math.Sin(castArgs[0]), nil
}

func lispCosine(args ...any) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("cos requires exactly 1 argument")
	}

	castArgs, err := toRational(args, "cos")
	if err != nil {
		return nil, err
	}

	return math.Cos(castArgs[0]), nil
}

func lispSqrt(args ...any) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("sqrt requires exactly 1 argument")
	}

	castArgs, err := toRational(args, "sqrt")
	if err != nil {
		return nil, err
	}
	arg := castArgs[0]

	if arg < 0 {
		return nil, fmt.Errorf("sqrt expects a postiive number, got %v", arg)
	}

	return math.Sqrt(arg), nil
}

// HELPERS

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

func simplifyNumber(c complex128) any {
	if imag(c) == 0 {
		realPart := real(c)
		if realPart == float64(int(realPart)) {
			return int(realPart) // Return int if whole number
		}
		return realPart // Return float64
	}
	return c // Return complex128
}
