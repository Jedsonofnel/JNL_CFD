package jnlisp

import (
	"fmt"
)

func eval(x exp, env *env) (exp, error) {
	if env == nil {
		panic("no environment passed to eval")
	}

	if sym, ok := x.(symbol); ok {
		val, exists := env.find(sym)
		if !exists {
			return nil, fmt.Errorf("undefined symbol: %s", sym)
		}
		return val, nil
	}

	// base types
	switch x.(type) {
	case int, float32, float64, complex64, complex128:
		return x, nil
	case bool:
		return x, nil
	case string:
		return x, nil
	}

	list, ok := x.(list)
	if !ok {
		return nil, fmt.Errorf("unexpected expression type, got %T", x)
	}

	if len(list) == 0 {
		return nil, fmt.Errorf("empty list cannot be evaluated")
	}

	if sym, ok := list[0].(symbol); ok {
		switch sym {
		case "if":
			return evalIf(list, env)
		case "define":
			return evalDefine(list, env)
		case "lambda":
			return evalLambda(list, env)
		case "and":
			return evalAnd(list, env)
		case "or":
			return evalOr(list, env)
		}
	}

	return evalApplication(list, env)
}

// SPECIAL FORMS

func evalIf(list list, env *env) (exp, error) {
	if len(list) != 4 {
		return nil, fmt.Errorf("if expects exactly 3 arguments (test consequence alternative), got %d", len(list)-1)
	}

	test, conseq, alt := list[1], list[2], list[3]
	testResult, err := eval(test, env)
	if err != nil {
		return nil, err
	}

	if testResult.(bool) {
		return eval(conseq, env)
	} else {
		return eval(alt, env)
	}
}

func evalDefine(l list, env *env) (exp, error) {
	if varName, ok := l[1].(symbol); ok {
		// handle variable
		if len(l) != 3 {
			return nil, fmt.Errorf("define (variable) expects exactly 2 arguments (symbol expression), got %d",
				len(l)-1)
		}

		defExp := l[2]
		defExpResult, err := eval(defExp, env)
		if err != nil {
			return nil, err
		}

		env.bind(varName, defExpResult)
		return defExpResult, nil
	}

	if funcDef, ok := l[1].(list); ok {
		// handle function definition
		funcName, ok := funcDef[0].(symbol)
		if !ok {
			return nil, fmt.Errorf("define (procedure) expects symbol as first parameter in parameter list, got %T",
				funcDef[0])
		}

		params := funcDef[1:]
		parms := make([]symbol, len(params))
		for i, param := range params {
			parm, ok := param.(symbol)
			if !ok {
				return nil, fmt.Errorf("define (procedure) expects symbols as proc parameters, got %T at position %d",
					param, i)
			}
			parms[i] = parm
		}

		body := l[2:]
		if len(body) == 0 {
			return nil, fmt.Errorf("define (procedure) body cannot be empty")
		}

		proc := &Procedure{
			name:    funcName.String(),
			parms:   parms,
			body:    body,
			closure: env,
		}

		env.bind(funcName, proc)
		return funcName, nil
	}

	// handle error
	return nil, fmt.Errorf("define expects parameter list (procedure) or symbol (variable) as argument 0 but got %T",
		l[1])
}

func evalLambda(l list, env *env) (exp, error) {
	if len(l) != 3 {
		return nil, fmt.Errorf("lambda expects exactly 2 arguments ((parms) expression), got %d", len(l)-1)
	}

	paramList, ok := l[1].(list)
	if !ok {
		return nil, fmt.Errorf("lambda expects list at argument position 0, got %T", l[1])
	}

	parms := make([]symbol, len(paramList))
	for i, p := range paramList {
		parm, ok := p.(symbol)
		if !ok {
			return nil, fmt.Errorf("lambda expects parameters to be symbols, got %T at parameter position %d",
				p, i)
		}
		parms[i] = parm
	}

	body := l[2:] // the rest
	if len(body) == 0 {
		return nil, fmt.Errorf("lambda expects body expression(s) but was empty")
	}

	return &Procedure{
		name:    "lambda",
		parms:   parms,
		body:    body,
		closure: env,
	}, nil
}

func evalAnd(list list, env *env) (exp, error) {
	for i := 1; i < len(list); i++ {
		result, err := eval(list[i], env)
		if err != nil {
			return nil, err
		}

		condition, ok := result.(bool)
		if !ok {
			return nil, fmt.Errorf("and expects boolean arguments, got %T at position %d", result, i-1)
		}

		if !condition {
			return false, nil
		}
	}

	return true, nil
}

func evalOr(list list, env *env) (exp, error) {
	for i := 1; i < len(list); i++ {
		result, err := eval(list[i], env)
		if err != nil {
			return nil, err
		}

		condition, ok := result.(bool)
		if !ok {
			return nil, fmt.Errorf("or expects boolean arguments, got %T at position %d", result, i-1)
		}

		if condition {
			return true, nil
		}
	}

	return false, nil
}

// NORMAL PROCEDURES

func evalApplication(list list, env *env) (exp, error) {
	proc, err := eval(list[0], env)
	if err != nil {
		return nil, err
	}

	// get args
	args := make([]any, len(list)-1)
	for i := range args {
		arg, err := eval(list[i+1], env)
		if err != nil {
			return nil, err
		}
		args[i] = arg
	}

	castProc, ok := proc.(*Procedure)
	if !ok {
		return nil, fmt.Errorf("cannot call non-procedure: %T", proc)
	}

	return castProc.Call(args...)
}
