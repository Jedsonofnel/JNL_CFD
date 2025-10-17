package jnlisp

import (
	"strconv"
)

// EVAL IMPLEMENTATION

func eval(expr expr, ctx *Context) (Atom, Error) {
	switch e := expr.(type) {
	case literalExpr:
		return evalLiteral(e)
	case symbolExpr:
		if ctx.importPrefix != "" {
			prefixedName := ctx.importPrefix + "/" + e.name
			if atom, exists := ctx.env.find(prefixedName); exists {
				return atom, nil
			}
		}

		if atom, exists := ctx.env.find(e.name); exists {
			return atom, nil
		}
		return nil, RuntimeError{Message: "undefined symbol: " + e.name}
	case vectorExpr:
		elements := make([]Atom, len(e.elements))
		for i, elem := range e.elements {
			evaluated, err := eval(elem, ctx)
			if err != nil {
				return nil, RuntimeError{Message: "vector element " + strconv.Itoa(i) + " > " + err.Error()}
			}
			elements[i] = evaluated
		}
		return VectorAtom{elements}, nil
	case tableExpr:
		return evalTable(e, ctx)

	// procedure calling
	case callExpr:
		return evalCall(e, ctx)
	case defineExpr:
		return evalDefine(e, ctx)
	case lambdaExpr:
		return evalLambda(e, ctx)
	case ifExpr:
		return evalIf(e, ctx)
	case beginExpr:
		return evalBegin(e, ctx)
	case setBangExpr:
		return evalSetBang(e, ctx)
	case importExpr:
		return evalImport(e, ctx)
	default:
		return nil, RuntimeError{Message: "unknown expression type"}
	}
}

// Primitive evaluation

func evalLiteral(literal literalExpr) (Atom, Error) {
	switch v := literal.value.(type) {
	case string:
		return StringAtom{v}, nil
	case int, float32, float64, complex64, complex128:
		return NumberAtom{v}, nil
	case bool:
		return BooleanAtom{v}, nil
	default:
		return nil, RuntimeError{Message: "unknown literal type"}
	}
}

func evalTable(table tableExpr, ctx *Context) (TableAtom, Error) {
	elements := make(map[string]Atom, len(table.elements))
	for k, v := range table.elements {
		evaluated, err := eval(v, ctx)
		if err != nil {
			return TableAtom{}, RuntimeError{Message: "table element :" + k + " > " + err.Error()}
		}
		elements[k] = evaluated
	}
	return TableAtom{elements}, nil
}

// Procedure evaluation

func evalCall(expr callExpr, ctx *Context) (Atom, Error) {
	proc, err := eval(expr.procedure, ctx)
	if err != nil {
		return nil, err
	}

	castProc, ok := CastAtom[ProcedureAtom](proc)
	if !ok {
		return nil, RuntimeError{
			Message: "cannot call non-procedure: " + proc.Type(),
		}
	}

	args := make([]Atom, len(expr.args))
	for i, argExpr := range expr.args {
		arg, err := eval(argExpr, ctx)
		if err != nil {
			return nil, err
		}
		args[i] = arg
	}

	kwargs, err := evalTable(expr.kwargs, ctx)
	if err != nil {
		return nil, err
	}

	return castProc.Call(args, kwargs, ctx)
}

func evalIf(expr ifExpr, ctx *Context) (Atom, Error) {
	testResult, err := eval(expr.predicate, ctx)
	if err != nil {
		return nil, err
	}

	boolean, ok := testResult.(BooleanAtom)
	if !ok {
		return nil, RuntimeError{Message: "if expects boolean predicate, got " + testResult.Type()}
	}

	if boolean.Value {
		return eval(expr.consequent, ctx)
	} else {
		return eval(expr.alternative, ctx)
	}
}

func evalDefine(expr defineExpr, ctx *Context) (Atom, Error) {
	value, err := eval(expr.binding, ctx)
	if err != nil {
		return nil, err
	}
	bindName := string(expr.name)
	if ctx.importPrefix != "" {
		bindName = ctx.importPrefix + "/" + bindName
	}

	// if defining a lambda then name the procedure
	if proc, ok := value.(ProcedureAtom); ok {
		if proc.name == "lambda" {
			proc.Procedure.name = bindName
		}
	}

	ctx.env.bind(bindName, value)
	return value, nil
}

func evalLambda(expr lambdaExpr, ctx *Context) (Atom, Error) {
	proc := &Procedure{
		name:         "lambda",
		params:       paramList{expr.args, expr.kwargs},
		body:         expr.procedure,
		closure:      ctx.env,
		definingCtx:  ctx,
		importPrefix: ctx.importPrefix,
	}

	return ProcedureAtom{proc}, nil
}

func evalBegin(expr beginExpr, ctx *Context) (Atom, Error) {
	// only return last result
	var result Atom
	var err Error
	for i := range expr.exprs {
		expr := expr.exprs[i]
		result, err = eval(expr, ctx)
		if err != nil {
			return nil, err
		}
	}

	return result, nil
}

// TODO: complete this
func evalSetBang(expr setBangExpr, ctx *Context) (Atom, Error) {
	return nil, nil
}

func evalImport(expr importExpr, ctx *Context) (Atom, Error) {
	return BooleanAtom{true}, ctx.ImportLibrary(expr.name, expr.prefix)
}
