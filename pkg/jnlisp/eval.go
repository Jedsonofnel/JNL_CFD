package jnlisp

import (
	"fmt"
)

func eval(x exp, env env) (exp, error) {
	if env == nil {
		panic("no environment passed to eval")
	}

	if sym, ok := x.(symbol); ok {
		val, exists := env[sym]
		if !exists {
			return nil, fmt.Errorf("undefined symbol: %s", sym)
		}
		return val, nil
	}

	switch x.(type) {
	case int, float32, float64, complex64, complex128:
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
		}
	}

	return evalApplication(list, env)
}

// SPECIAL FORMS

func evalIf(list list, env env) (exp, error) {
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

func evalDefine(list list, env env) (exp, error) {
	if len(list) != 3 {
		return nil, fmt.Errorf("define expects exactly 2 arguments (symbol expression), got %d", len(list)-1)
	}

	sym, defExp := list[1], list[2]
	defExpResult, err := eval(defExp, env)
	if err != nil {
		return nil, err
	}

	castSym, ok := sym.(symbol)
	if !ok {
		return nil, fmt.Errorf("define expects symbol at position 0, got %T", sym)
	}

	env[castSym] = defExpResult
	return defExpResult, nil
}

// NORMAL PROCEDURES

func evalApplication(list list, env env) (exp, error) {
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

	castProc, ok := proc.(LispFunc)
	if !ok {
		return nil, fmt.Errorf("cannot call non-procedure: %T", proc)
	}

	return castProc(args...)
}
