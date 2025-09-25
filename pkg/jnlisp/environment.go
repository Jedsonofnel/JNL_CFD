package jnlisp

import (
	"fmt"
	"math"
)

type env struct {
	bindings map[symbol]any
	outer    *env
}

func newEnv(outer *env) *env {
	return &env{
		bindings: make(map[symbol]any),
		outer:    outer,
	}
}

func (e *env) defineProc(name symbol, p ProcFunc) {
	procedure := &Procedure{
		proc:    p, // this means it's got a concrete go procedure so no need for body/params
		name:    string(name),
		closure: e,
	}

	e.bindings[symbol(name)] = procedure
}

func (e *env) find(s symbol) (exp, bool) {
	val, exists := e.bindings[s]
	if exists {
		return val, true
	}

	if e.outer != nil {
		return e.outer.find(s)
	}

	return nil, false
}

func (e *env) bind(s symbol, exp exp) {
	e.bindings[s] = exp
}

func newStandardEnv() (e *env) {
	e = newEnv(nil)

	e.defineProc("+", lispAdd)
	e.defineProc("-", lispSubtract)
	e.defineProc("*", lispMultiply)
	e.defineProc("/", lispDivide)
	e.defineProc("%", lispModulo)
	e.defineProc("sin", lispSine)
	e.defineProc("cos", lispCosine)
	e.defineProc("sqrt", lispSqrt)

	e.defineProc(">", lispGreaterThan)
	e.defineProc("<", lispLessThan)
	e.defineProc("=", lispEqual)
	e.defineProc("not", lispNot)

	return
}

type table map[string]any // TOOD move this to parser when I add a vector type etc

type ProcFunc func(args []any, kwargs table) (any, error)

type paramList struct {
	positional []symbol
	named      []symbol
}

type Procedure struct {
	proc    ProcFunc
	name    string
	params   paramList
	body    []exp
	closure *env
}

func (p *Procedure) Call(args []any, kwargs table) (exp, error) {
	if p.proc != nil { // given a go binding
		return p.proc(args, kwargs)
	}

	activationEnv := newEnv(p.closure)

	if len(args) != len(p.params.positional) {
		return nil, fmt.Errorf("'%s' expects %d positional args, got %d",
			p.name, len(p.params.positional), len(args))
	}

	// bind positional parameters
	for i, param := range p.params.positional {
		activationEnv.bind(param, args[i])
	}

	// bind named parameters from table
	for _, namedParam := range p.params.named {
		paramName := string(namedParam)
		if value, exists := kwargs[paramName]; exists {
			activationEnv.bind(namedParam, value)
		} else {
			// TODO consider defaults later
			activationEnv.bind(namedParam, nil)
		}
	}

	var result exp
	var err error
	for _, expr := range p.body {
		result, err = eval(expr, activationEnv)
		if err != nil {
			return nil, err
		}
	}

	return result, err
}

// STANDARD MATHS

func lispAdd(args []any, _ table) (any, error) {
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

func lispSubtract(args []any, _ table) (any, error) {
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

func lispMultiply(args []any, _ table) (any, error) {
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

func lispDivide(args []any, _ table) (any, error) {
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

func lispModulo(args []any, _ table) (any, error) {
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

func lispSine(args []any, _ table) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("sin expects exactly 1 argument, got %d", len(args))
	}

	castArgs, err := toRational(args, "sin")
	if err != nil {
		return nil, err
	}

	return math.Sin(castArgs[0]), nil
}

func lispCosine(args []any, _ table) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("cos expects exactly 1 argument, got %d", len(args))
	}

	castArgs, err := toRational(args, "cos")
	if err != nil {
		return nil, err
	}

	return math.Cos(castArgs[0]), nil
}

func lispSqrt(args []any, _ table) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("sqrt expects exactly 1 argument, got %d", len(args))
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

// COMPARISONS

func lispGreaterThan(args []any, _ table) (any, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("> expects exactly 2 arguments, got %d", len(args))
	}

	castArgs, err := toRational(args, ">")
	if err != nil {
		return nil, err
	}

	return castArgs[0] > castArgs[1], nil
}

func lispLessThan(args []any, _ table) (any, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("< expects exactly 2 arguments, got %d", len(args))
	}

	castArgs, err := toRational(args, "<")
	if err != nil {
		return nil, err
	}

	return castArgs[0] < castArgs[1], nil
}

func lispEqual(args []any, _ table) (any, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("= expects at least 2 arguments, got %d", len(args))
	}

	first := args[0]
	for i := 1; i < len(args); i++ {
		if !isEqual(first, args[i]) {
			return false, nil
		}
	}

	return true, nil
}

func lispNot(args []any, _ table) (any, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("not expects at least 1 argument, got %d", len(args))
	}

	condition, ok := args[0].(bool)
	if !ok {
		return nil, fmt.Errorf("not expects a boolean argument, got %T", args[0])
	}

	return !condition, nil
}

// HELPERS

func isEqual(a, b any) bool {
	if isNumber(a) && isNumber(b) {
		castArgs, _ := toComplex([]any{a, b}, "")
		return castArgs[0] == castArgs[1]
	}

	switch va := a.(type) {
	case bool:
		if vb, ok := b.(bool); ok {
			return va == vb
		}
	case string:
		if vb, ok := b.(string); ok {
			return va == vb
		}
	}

	return false
}

func isNumber(x any) bool {
	switch x.(type) {
	case int, float32, float64, complex64, complex128:
		return true
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
