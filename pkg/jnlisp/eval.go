package jnlisp

import (
	"strconv"
)

// EVAL IMPLEMENTATION

func eval(expr any, ctx *Context) (Atom, Error) {
	switch v := expr.(type) {
	case Atom:
		// already evaluated, return as-is
		return v, nil

	case listRaw:
		return evalList(v, ctx)

	case vectorRaw:
		elements := make([]Atom, len(v))
		for i, elem := range v {
			evaluated, err := eval(elem, ctx)
			if err != nil {
				return nil, RuntimeError{Message: "vector element " + strconv.Itoa(i) + " > " + err.Error()}
			}
			elements[i] = evaluated
		}
		return VectorAtom{elements}, nil

	case symbol:
		symbolName := string(v)

		if ctx.importPrefix != "" {
			prefixedName := ctx.importPrefix + "/" + symbolName
			if atom, exists := ctx.env.find(prefixedName); exists {
				return atom, nil
			}
		}

		if atom, exists := ctx.env.find(symbolName); exists {
			return atom, nil
		}
		return nil, RuntimeError{Message: "undefined symbol: " + string(v)}

	case string:
		return StringAtom{v}, nil

	case int, float32, float64, complex64, complex128:
		return NumberAtom{v}, nil

	case bool:
		return BooleanAtom{v}, nil

	default:
		return nil, RuntimeError{Message: "unknown expression type!"}
	}
}

func evalList(list listRaw, ctx *Context) (Atom, Error) {
	if len(list) == 0 {
		return nil, RuntimeError{Message: "empty list cannot be evaluated"}
	}

	// special forms
	if sym, ok := list[0].(symbol); ok {
		switch sym {
		case "if":
			return evalIf(list, ctx)
		case "define":
			return evalDefine(list, ctx)
		case "lambda":
			return evalLambda(list, ctx)
		case "import":
			return evalImport(list, ctx)
		}
	}

	return evalCall(list, ctx)
}

// SPECIAL FORMS

func evalIf(list listRaw, ctx *Context) (Atom, Error) {
	if len(list) != 4 {
		return nil, RuntimeError{Message: "error parsing if"}
	}

	test, conseq, alt := list[1], list[2], list[3]
	testResult, err := eval(test, ctx)
	if err != nil {
		return nil, err
	}

	boolean, ok := testResult.(BooleanAtom)
	if !ok {
		return nil, RuntimeError{Message: "if expecting boolean predicate, got " + testResult.Type()}
	}

	if boolean.Value {
		return eval(conseq, ctx)
	} else {
		return eval(alt, ctx)
	}
}

func evalDefine(list listRaw, ctx *Context) (Atom, Error) {
	if varName, ok := list[1].(symbol); ok {
		// handle variable
		if len(list) != 3 {
			return nil, RuntimeError{Message: "error parsing define"}
		}

		defExp := list[2]
		defExpResult, err := eval(defExp, ctx)
		if err != nil {
			return nil, err
		}

		bindName := string(varName)
		if ctx.importPrefix != "" {
			bindName = ctx.importPrefix + "/" + bindName
		}
		return ctx.env.bind(bindName, defExpResult), nil
	}

	// handle function definition
	if funcDef, ok := list[1].(listRaw); ok {
		funcName, ok := funcDef[0].(symbol)
		if !ok {
			return nil, RuntimeError{Message: "error parsing define"}
		}

		paramList, err := parseParamList(funcDef[1:])
		if err != nil {
			return nil, RuntimeError{"define " + string(funcName) + " > " + err.Error()}
		}

		body := list[2:]
		if len(body) == 0 {
			return nil, RuntimeError{"define (procedure) body cannot be empty"}
		}

		proc := &Procedure{
			name:         string(funcName),
			params:       paramList,
			body:         body,
			closure:      ctx.env,
			definingCtx:  ctx,
			importPrefix: ctx.importPrefix,
		}

		bindName := string(funcName)
		if ctx.importPrefix != "" {
			bindName = ctx.importPrefix + "/" + bindName
		}

		return ctx.env.bind(bindName, ProcedureAtom{proc}), nil
	}

	// handle error
	return nil, RuntimeError{Message: "error parsing define"}
}

func evalLambda(list listRaw, ctx *Context) (Atom, Error) {
	if len(list) != 3 {
		return nil, RuntimeError{Message: "error parsing lambda"}
	}

	params, ok := list[1].(listRaw)
	if !ok {
		return nil, RuntimeError{Message: "error parsing lambda"}
	}

	paramList, err := parseParamList(params)
	if err != nil {
		return nil, RuntimeError{"lambda param parsing > " + err.Error()}
	}

	body := list[2:] // the rest
	if len(body) == 0 {
		return nil, RuntimeError{Message: "error parsing lambda"}
	}

	proc := &Procedure{
		name:         "lambda",
		params:       paramList,
		body:         body,
		closure:      ctx.env,
		definingCtx:  ctx,
		importPrefix: ctx.importPrefix,
	}

	return ProcedureAtom{proc}, nil
}

func evalImport(list listRaw, ctx *Context) (Atom, Error) {
	if len(list) != 2 && len(list) != 3 {
		return nil, RuntimeError{"Error parsing import"}
	}

	libName, ok := list[1].(string)
	if !ok {
		return nil, RuntimeError{"Error parsing import"}
	}

	prefix := libName // Default prefix
	if len(list) == 3 {
		if prefixArg, ok := list[2].(string); ok {
			prefix = prefixArg
		} else {
			return nil, RuntimeError{"Error parsing import"}
		}
	}

	return BooleanAtom{true}, ctx.ImportLibrary(libName, prefix)
}

// NORMAL PROCEDURES

func evalCall(list listRaw, ctx *Context) (Atom, Error) {
	keywordIdx := findFirstKeyword(list)

	proc, err := eval(list[0], ctx)
	if err != nil {
		return nil, err
	}

	castProc, ok := As[ProcedureAtom](proc)
	if !ok {
		return nil, RuntimeError{
			Message: "cannot call non-procedure: %s" + proc.Type(),
		}
	}

	if keywordIdx == -1 {
		// No keywords - regular call
		args := make([]Atom, len(list)-1)
		for i := 1; i < len(list); i++ {
			args[i-1], err = eval(list[i], ctx)
			if err != nil {
				return nil, RuntimeError{
					Message: "parsing args for " + castProc.name + ": " + err.Error(),
				}
			}
		}

		return castProc.Call(args, make(Table), ctx)
	}
	// keywords present
	positionalExpr := list[1:keywordIdx]
	keywordSection := list[keywordIdx:]

	if (len(keywordSection) % 2) != 0 {
		return nil, RuntimeError{
			Message: "error parsing keyword args",
		}
	}

	args := make([]Atom, len(positionalExpr))
	for i, expr := range positionalExpr {
		arg, err := eval(expr, ctx)
		if err != nil {
			return nil, RuntimeError{
				Message: "parsing args for " + castProc.name + ": " + err.Error(),
			}
		}
		args[i] = arg
	}

	// build a table from keywords
	kwargs := make(Table)
	for i := 0; i < len(keywordSection); i += 2 {
		key, ok := keywordSection[i].(keyword)
		if !ok {
			return nil, RuntimeError{
				Message: "error parsing keyword args",
			}
		}

		value, err := eval(keywordSection[i+1], ctx)
		if err != nil {
			return nil, RuntimeError{
				Message: "parsing args for " + castProc.name + ": " + err.Error(),
			}
		}

		kwargs[string(key)] = value
	}

	return castProc.Call(args, kwargs, ctx)
}

// HELPERS

func parseParamList(paramExpr listRaw) (paramList, error) {
	var params paramList

	ampersandEncountered := false
	for _, param := range paramExpr {
		sym, ok := param.(symbol)
		if !ok {
			return params, RuntimeError{"Error parsing params"}
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

func findFirstKeyword(list listRaw) int {
	for i, exp := range list {
		if _, ok := exp.(keyword); ok {
			return i
		}
	}
	return -1
}
