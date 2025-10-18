package jnlisp

import (
	"strconv"
)

const MaxRecursionDepth = 1000

// EVAL IMPLEMENTATION

func (ctx *Context) eval(expr expr, env *env, depth int) (Atom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	switch e := expr.(type) {
	case literalExpr:
		return ctx.evalLiteral(e)
	case symbolExpr:
		if atom, exists := env.find(e.name); exists {
			return atom, nil
		}
		return nil, RuntimeError{Message: "undefined symbol: " + e.name}
	case vectorExpr:
		elements := make([]Atom, len(e.elements))
		for i, elem := range e.elements {
			evaluated, err := ctx.eval(elem, env, depth+1)
			if err != nil {
				return nil, RuntimeError{Message: "vector element " + strconv.Itoa(i) + " > " + err.Error()}
			}
			elements[i] = evaluated
		}
		return VectorAtom(elements), nil
	case tableExpr:
		return ctx.evalTable(e, env, depth+1)

	// procedure calling
	case callExpr:
		return ctx.evalCall(e, env, depth+1)
	case defineExpr:
		return ctx.evalDefine(e, env, depth+1)
	case lambdaExpr:
		return ctx.evalLambda(e, env, depth+1)
	case ifExpr:
		return ctx.evalIf(e, env, depth+1)
	case beginExpr:
		return ctx.evalBegin(e, env, depth+1)
	case setBangExpr:
		return evalSetBang(e, ctx, depth+1)
	case importExpr:
		return evalImport(e, ctx)
	default:
		return nil, RuntimeError{Message: "unknown expression type"}
	}
}

// Primitive evaluation

func (ctx *Context) evalLiteral(literal literalExpr) (Atom, Error) {
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

func (ctx *Context) evalTable(table tableExpr, env *env, depth int) (TableAtom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	elements := make(map[string]Atom, len(table.elements))
	for k, v := range table.elements {
		evaluated, err := ctx.eval(v, env, depth+1)
		if err != nil {
			return TableAtom{}, RuntimeError{Message: "table element :" + k + " > " + err.Error()}
		}
		elements[k] = evaluated
	}
	return TableAtom(elements), nil
}

// Procedure evaluation

func (ctx *Context) evalCall(expr callExpr, env *env, depth int) (Atom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	fnAtom, err := ctx.eval(expr.fn, env, depth+1)
	if err != nil {
		return nil, err
	}

	fn, ok := CastAtom[Function](fnAtom)
	if !ok {
		return nil, RuntimeError{
			Message: "cannot call non-procedure: " + fn.Type(),
		}
	}

	args := make([]Atom, len(expr.args))
	for i, argExpr := range expr.args {
		arg, err := ctx.eval(argExpr, env, depth+1)
		if err != nil {
			return nil, err
		}
		args[i] = arg
	}

	kwargs, err := ctx.evalTable(expr.kwargs, env, depth+1)
	if err != nil {
		return nil, err
	}

	return fn.Call(args, kwargs, depth+1)
}

func (ctx *Context) evalIf(expr ifExpr, env *env, depth int) (Atom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	testResult, err := ctx.eval(expr.predicate, env, depth+1)
	if err != nil {
		return nil, err
	}

	boolean, ok := testResult.(BooleanAtom)
	if !ok {
		return nil, RuntimeError{Message: "if expects boolean predicate, got " + testResult.Type()}
	}

	if boolean.Value {
		return ctx.eval(expr.consequent, env, depth+1)
	} else {
		return ctx.eval(expr.alternative, env, depth+1)
	}
}

func (ctx *Context) evalDefine(expr defineExpr, env *env, depth int) (Atom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	value, err := ctx.eval(expr.binding, env, depth+1)
	if err != nil {
		return nil, err
	}

	name := string(expr.name)

	// if defining a lambda then name it
	if fn, ok := value.(*lispFunction); ok {
		if fn.name == "lambda" {
			fn.name = name
		}
	}

	env.bind(name, value)
	return value, nil
}

func (ctx *Context) evalLambda(expr lambdaExpr, env *env, depth int) (Function, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	fn := &lispFunction{
		name:    "lambda",
		params:  fnParams{expr.args, expr.kwargs},
		body:    expr.fn,
		closure: env,
		ctx:     ctx,
	}

	return fn, nil
}

func (ctx *Context) evalBegin(expr beginExpr, env *env, depth int) (Atom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	// only return last result
	var result Atom
	var err Error
	for i := range expr.exprs {
		expr := expr.exprs[i]
		result, err = ctx.eval(expr, env, depth+1)
		if err != nil {
			return nil, err
		}
	}

	return result, nil
}

// TODO: complete this
func evalSetBang(expr setBangExpr, ctx *Context, depth int) (Atom, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	return nil, nil
}

// TODO: complete this
func evalImport(expr importExpr, ctx *Context) (Atom, Error) {
	return BooleanAtom{true}, ctx.ImportPackage(expr.name, expr.prefix)
}
