package jnlisp

import (
	"strconv"
)

const MaxRecursionDepth = 1000

// EVAL IMPLEMENTATION

func (vm *VM) eval(expr expr, env *env, depth int) (Sexp, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	switch e := expr.(type) {
	case literalExpr:
		return e.sexp, nil
	case symbolExpr:
		if sexp, exists := env.find(e.name); exists {
			return sexp, nil
		}
		return nil, RuntimeError{Message: "undefined symbol: " + e.name}
	case vectorExpr:
		elements := make([]Sexp, len(e.elements))
		for i, elem := range e.elements {
			evaluated, err := vm.eval(elem, env, depth+1)
			if err != nil {
				return nil, RuntimeError{Message: "vector element " + strconv.Itoa(i) + " > " + err.Error()}
			}
			elements[i] = evaluated
		}
		return Vector(elements), nil
	case tableExpr:
		return vm.evalTable(e, env, depth+1)

	// procedure calling
	case callExpr:
		return vm.evalCall(e, env, depth+1)
	case defineExpr:
		return vm.evalDefine(e, env, depth+1)
	case lambdaExpr:
		return vm.evalLambda(e, env, depth+1)
	case ifExpr:
		return vm.evalIf(e, env, depth+1)
	case beginExpr:
		return vm.evalBegin(e, env, depth+1)
	case setBangExpr:
		return evalSetBang(e, vm, depth+1)
	case importExpr:
		return evalImport(e, vm)
	default:
		return nil, RuntimeError{Message: "unknown expression type"}
	}
}

// Primitive evaluation

func (vm *VM) evalTable(table tableExpr, env *env, depth int) (Table, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	elements := make(map[string]Sexp, len(table.elements))
	for k, v := range table.elements {
		evaluated, err := vm.eval(v, env, depth+1)
		if err != nil {
			return nil, RuntimeError{Message: "table element :" + k + " > " + err.Error()}
		}
		elements[k] = evaluated
	}
	return Table(elements), nil
}

// Procedure evaluation

func (vm *VM) evalCall(expr callExpr, env *env, depth int) (Sexp, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	fnSexp, err := vm.eval(expr.fn, env, depth+1)
	if err != nil {
		return nil, err
	}

	fn, ok := fnSexp.(Function)
	if !ok {
		return nil, RuntimeError{
			Message: "cannot call non-procedure: " + fn.Type(),
		}
	}

	args := make([]Sexp, len(expr.args))
	for i, argExpr := range expr.args {
		arg, err := vm.eval(argExpr, env, depth+1)
		if err != nil {
			return nil, err
		}
		args[i] = arg
	}

	kwargs, err := vm.evalTable(expr.kwargs, env, depth+1)
	if err != nil {
		return nil, err
	}

	return fn.Call(args, kwargs, depth+1)
}

func (vm *VM) evalIf(expr ifExpr, env *env, depth int) (Sexp, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	testResult, err := vm.eval(expr.predicate, env, depth+1)
	if err != nil {
		return nil, err
	}

	boolean, ok := testResult.(Boolean)
	if !ok {
		return nil, RuntimeError{Message: "if expects boolean predicate, got " + testResult.Type()}
	}

	if bool(boolean) {
		return vm.eval(expr.consequent, env, depth+1)
	} else {
		return vm.eval(expr.alternative, env, depth+1)
	}
}

func (vm *VM) evalDefine(expr defineExpr, env *env, depth int) (Sexp, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	value, err := vm.eval(expr.binding, env, depth+1)
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

func (vm *VM) evalLambda(expr lambdaExpr, env *env, depth int) (Function, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	fn := &lispFunction{
		name:    "lambda",
		params:  fnParams{expr.args, expr.kwargs},
		body:    expr.fn,
		closure: env,
		vm:     vm,
	}

	return fn, nil
}

func (vm *VM) evalBegin(expr beginExpr, env *env, depth int) (Sexp, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	// only return last result
	var result Sexp
	var err Error
	for i := range expr.exprs {
		expr := expr.exprs[i]
		result, err = vm.eval(expr, env, depth+1)
		if err != nil {
			return nil, err
		}
	}

	return result, nil
}

// TODO: complete this
func evalSetBang(expr setBangExpr, vm *VM, depth int) (Sexp, Error) {
	if depth > MaxRecursionDepth {
		return nil, RuntimeError{Message: "recursion limit exceeded"}
	}

	return nil, nil
}

func evalImport(expr importExpr, vm *VM) (Sexp, Error) {
	return Boolean(true), vm.ImportPackage(expr.name, expr.prefix)
}
