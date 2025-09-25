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

	// handle function definition
	if funcDef, ok := l[1].(list); ok {
		funcName, ok := funcDef[0].(symbol)
		if !ok {
			return nil, fmt.Errorf("define (procedure) expects symbol as first parameter in parameter list, got %T",
				funcDef[0])
		}

		paramList, err := parseParamList(funcDef[1:])
		if err != nil {
			return nil, fmt.Errorf("define (procedure) > %w", err)
		}

		body := l[2:]
		if len(body) == 0 {
			return nil, fmt.Errorf("define (procedure) body cannot be empty")
		}

		proc := &Procedure{
			name:    string(funcName),
			params:  paramList,
			body:    body,
			closure: env,
		}

		env.bind(funcName, proc)
		return funcName, nil
	}

	// handle error
	return nil, fmt.Errorf("define expects parameter list (procedure) or symbol (variable) as arg 0 but got %T",
		l[1])
}

func evalLambda(l list, env *env) (exp, error) {
	if len(l) != 3 {
		return nil, fmt.Errorf("lambda expects exactly 2 args ((params) expression), got %d", len(l)-1)
	}

	paramList, err := parseParamList(l[1:])
	if err != nil {
		return nil, fmt.Errorf("lambda > %w", err)
	}

	body := l[2:] // the rest
	if len(body) == 0 {
		return nil, fmt.Errorf("lambda expects body expression(s) but was empty")
	}

	return &Procedure{
		name:    "lambda",
		params:  paramList,
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
	keywordIdx := findFirstKeyword(list)

	proc, err := eval(list[0], env)
	if err != nil {
		return nil, err
	}

	castProc, ok := proc.(*Procedure)
	if !ok {
		return nil, fmt.Errorf("cannot call non-procedure: %T", proc)
	}

	if keywordIdx == -1 {
		// No keywords - regular call
		args := make([]any, len(list)-1)
		for i := 1; i < len(list); i++ {
			args[i-1], err = eval(list[i], env)
			if err != nil {
				return nil, fmt.Errorf("%s parsing args > %w", castProc.name, err)
			}
		}

		return castProc.Call(args, make(table))
	}
	// keywords present
	positionalExpr := list[1:keywordIdx]
	keywordSection := list[keywordIdx:]

	if (len(keywordSection) % 2) != 0 {
		return nil, fmt.Errorf("%s parsing args > badly-formed keyword args, expected even number of terms (:key value) but got %d",
			castProc.name, len(keywordSection))
	}

	args := make([]any, len(positionalExpr))
	for i, expr := range positionalExpr {
		arg, err := eval(expr, env)
		if err != nil {
			return nil, fmt.Errorf("%s parsing args > %w", castProc.name, err)
		}
		args[i] = arg
	}

	// build a table from keywords
	kwargs := make(table)
	for i := 0; i < len(keywordSection); i += 2 {
		key, ok := keywordSection[i].(keyword)
		if !ok {
			return nil, fmt.Errorf("%s parsing args > badly-formed keyword args, expected keyword at position %d, got %T",
				castProc.name, i+len(positionalExpr), keywordSection[i])
		}

		value, err := eval(keywordSection[i+1], env)
		if err != nil {
			return nil, fmt.Errorf("%s parsing args > %w", castProc.name, err)
		}

		kwargs[string(key)] = value
	}

	return castProc.Call(args, kwargs)
}

// HELPERS

func parseParamList(paramExpr exp) (paramList, error) {
	var params paramList
	l, ok := paramExpr.(list)
	if !ok {
		return params, fmt.Errorf("expects list for parameters but got %T", paramExpr)
	}

	ampersandEncountered := false
	for i, param := range l {
		sym, ok := param.(symbol)
		if !ok {
			return params, fmt.Errorf("expects symbols as parameters but got %T at position %d", param, i)
		}

		if sym == symbol("&") {
			ampersandEncountered = true
			continue
		}

		if !ampersandEncountered {
			params.positional = append(params.positional, sym)
		} else {
			params.named = append(params.named, sym)
		}
	}

	return params, nil
}

func findFirstKeyword(l list) int {
	for i, exp := range l {
		if _, ok := exp.(keyword); ok {
			return i
		}
	}
	return -1
}
