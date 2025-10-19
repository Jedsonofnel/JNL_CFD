package jnlisp

import (
	"strconv"
)

const maxExpansionDepth = 1000

func expand(sexp Sexp, depth int) (Sexp, Error) {
	if depth > maxExpansionDepth {
		return sexp, ExpansionError{
			Message: "expansion depth exceeded at " + strconv.Itoa(depth),
		}
	}

	switch r := sexp.(type) {
	case List:
		if len(r) == 0 {
			return r, nil
		}

		if sym, ok := r[0].(Symbol); ok {
			// TODO: recursive macro expansion here

			// built-in expansions
			switch sym {
			case "define":
				expanded, err := expandDefine(r[1:])
				if err != nil {
					return nil, err
				}
				r = expanded.(List) // fall through to child recursion
			case "lambda":
				expanded, err := expandLambda(r[1:])
				if err != nil {
					return nil, err
				}
				r = expanded.(List)
			case "let":
				expanded, err := expandLet(r[1:])
				if err != nil {
					return nil, err
				}
				return expand(expanded, depth+1)
			case "and":
				expanded := expandAnd(r[1:])
				return expand(expanded, depth+1)
			case "or":
				expanded := expandOr(r[1:], depth)
				return expand(expanded, depth+1)
			}
		}

		// not a macro - recurse into children
		result := make(List, len(r))
		for i, elem := range r {
			// don't increment depth as this won't loop
			expanded, err := expand(elem, depth)
			if err != nil {
				return nil, err
			}
			result[i] = expanded
		}
		return result, nil
	case Vector:
		result := make(Vector, len(r))
		for i, elem := range r {
			expanded, err := expand(elem, depth)
			if err != nil {
				return nil, err
			}
			result[i] = expanded
		}
		return result, nil
	case Table:
		for kword, value := range r {
			expanded, err := expand(value, depth)
			if err != nil {
				return nil, err
			}
			r[kword] = expanded
		}
		return r, nil
	default:
		return sexp, nil // most types don't need expansion
	}
}

// BUILT IN EXPANSIONS (could eventually be superseded by macros)

func expandDefine(args List) (Sexp, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "define expects binding details and at least one body expression",
		}
	}

	// early termination if simple lexical binding
	if sym, ok := args[0].(Symbol); ok {
		defineSym := List{Symbol("define"), sym}
		defineSym = append(defineSym, args[1:]...)
		return defineSym, nil
	}

	funcArgs, ok := args[0].(List)
	if !ok || len(funcArgs) == 0 {
		return nil, ExpansionError{
			Message: "define expects a symbol or a list of symbols as first argument",
		}
	}

	funcSymArgs := make(List, len(funcArgs))

	for i := range funcArgs {
		if sym, ok := funcArgs[i].(Symbol); ok {
			funcSymArgs[i] = sym
			continue
		}

		return nil, ExpansionError{
			Message: "define (procedure) expects a list of symbols as first argument",
		}
	}

	lambda := List{Symbol("lambda"), funcSymArgs[1:]}
	lambda = append(lambda, args[1:]...)
	defineProc := List{Symbol("define"), funcSymArgs[0], lambda}
	return defineProc, nil
}

func expandLambda(args List) (Sexp, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "lambda expects at least 2 arguments",
		}
	}

	// early termination if just one body
	if len(args) == 2 {
		return List{Symbol("lambda"), args[0], args[1]}, nil
	}

	// expand multiple bodies to use begin
	bodies := args[1:]
	begin := List{Symbol("begin")}
	begin = append(begin, bodies...)

	return List{Symbol("lambda"), args[0], begin}, nil
}

func expandLet(args List) (Sexp, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "let expects bindings and at least one body expression",
		}
	}

	bindings, ok := args[0].(List)
	if !ok {
		return nil, &ExpansionError{
			Message: "let expects a list of bindings as arg 1",
		}
	}

	names := make(List, 0, len(bindings))
	values := make(List, 0, len(bindings))

	for i := range bindings {
		binding, ok := bindings[i].(List)
		errMsg := "let expects bindings to be (symbol value) pairs"
		if !ok || len(binding) != 2 {
			return nil, &ExpansionError{Message: errMsg}
		}

		name, ok := binding[0].(Symbol)
		if !ok {
			return nil, &ExpansionError{Message: errMsg}
		}

		names = append(names, name)
		values = append(values, binding[1])
	}

	lambda := List{Symbol("lambda"), names}
	lambda = append(lambda, args[1:]...)

	call := List{lambda}
	call = append(call, values...)

	return call, nil
}

func expandAnd(args List) Sexp {
	if len(args) == 0 {
		return Boolean(true)
	}

	if len(args) == 1 {
		return args[0]
	}

	rest := List{Symbol("and")}
	rest = append(rest, args[1:]...)

	// short circuit if it's false
	return List{Symbol("if"), args[0], rest, Boolean(false)}
}

func expandOr(args List, depth int) Sexp {
	if len(args) == 0 {
		return Boolean(false)
	}

	if len(args) == 1 {
		return args[0]
	}

	tmpSym := Symbol("#tmp" + strconv.Itoa(depth))
	rest := List{Symbol("or")}
	rest = append(rest, args[1:]...)

	return List{
		Symbol("let"),
		List{List{tmpSym, args[0]}},
		List{Symbol("if"), tmpSym, tmpSym, rest},
	}
}
