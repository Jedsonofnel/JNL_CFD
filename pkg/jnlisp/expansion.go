package jnlisp

import (
	"strconv"
)

const maxExpansionDepth = 1000

func expand(raw any) (any, Error) {
	return expandWithDepth(raw, 0)
}

func expandWithDepth(raw any, depth int) (any, Error) {
	if depth > maxExpansionDepth {
		return raw, ExpansionError{
			Message: "expansion depth exceeded at " + strconv.Itoa(depth),
		}
	}

	switch r := raw.(type) {
	case listRaw:
		if len(r) == 0 {
			return r, nil
		}

		if sym, ok := r[0].(symbol); ok {
			// TODO: recursive macro expansion here

			// built-in expansions
			switch sym {
			case "define":
				expanded, err := expandDefine(r[1:])
				if err != nil {
					return errorRaw{}, err
				}
				r = expanded.(listRaw) // fall through to child recursion
			case "lambda":
				expanded, err := expandLambda(r[1:])
				if err != nil {
					return errorRaw{}, err
				}
				r = expanded.(listRaw)
			case "let":
				expanded, err := expandLet(r[1:])
				if err != nil {
					return errorRaw{}, err
				}
				return expandWithDepth(expanded, depth+1)
			case "and":
				expanded := expandAnd(r[1:])
				return expandWithDepth(expanded, depth+1)
			case "or":
				expanded := expandOr(r[1:], depth)
				return expandWithDepth(expanded, depth+1)
			}
		}

		// not a macro - recurse into children
		result := make(listRaw, len(r))
		for i, elem := range r {
			// don't increment depth as this won't loop
			expanded, err := expandWithDepth(elem, depth)
			if err != nil {
				return nil, err
			}
			result[i] = expanded
		}
		return result, nil
	case vectorRaw:
		result := make(vectorRaw, len(r))
		for i, elem := range r {
			expanded, err := expandWithDepth(elem, depth)
			if err != nil {
				return nil, err
			}
			result[i] = expanded
		}
		return result, nil
	case tableRaw:
		result := make(tableRaw, len(r))
		for i, elem := range r {
			expanded, err := expandWithDepth(elem, depth)
			if err != nil {
				return nil, err
			}
			result[i] = expanded
		}
		return result, nil
	default:
		return raw, nil // most types don't need expansion
	}
}

// BUILT IN EXPANSIONS (will eventually be superseded by macros)

func expandDefine(args listRaw) (any, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "define expects binding details and at least one body expression",
		}
	}

	// early termination if simple lexical binding
	if sym, ok := args[0].(symbol); ok {
		defineSym := listRaw{symbol("define"), sym}
		defineSym = append(defineSym, args[1:]...)
		return defineSym, nil
	}

	funcArgs, ok := args[0].(listRaw)
	if !ok || len(funcArgs) == 0 {
		return nil, ExpansionError{
			Message: "define expects a symbol or a list of symbols as first argument",
		}
	}

	funcSymArgs := make(listRaw, len(funcArgs))

	for i := range funcArgs {
		if sym, ok := funcArgs[i].(symbol); ok {
			funcSymArgs[i] = sym
			continue
		}

		return nil, ExpansionError{
			Message: "define (procedure) expects a list of symbols as first argument",
		}
	}

	lambda := listRaw{symbol("lambda"), funcSymArgs[1:]}
	lambda = append(lambda, args[1:]...)
	defineProc := listRaw{symbol("define"), funcSymArgs[0], lambda}
	return defineProc, nil
}

func expandLambda(args listRaw) (any, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "lambda expects at least 2 arguments",
		}
	}

	// early termination if just one body
	if len(args) == 2 {
		return listRaw{symbol("lambda"), args[0], args[1]}, nil
	}

	// expand multiple bodies to use begin
	bodies := args[1:]
	begin := listRaw{symbol("begin")}
	begin = append(begin, bodies...)

	return listRaw{symbol("lambda"), args[0], begin}, nil
}

func expandLet(args listRaw) (any, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "let expects bindings and at least one body expression",
		}
	}

	bindings, ok := args[0].(listRaw)
	if !ok {
		return nil, &ExpansionError{
			Message: "let expects a list of bindings as arg 1",
		}
	}

	names := make(listRaw, 0, len(bindings))
	values := make(listRaw, 0, len(bindings))

	for i := range bindings {
		binding, ok := bindings[i].(listRaw)
		errMsg := "let expects bindings to be (symbol value) pairs"
		if !ok || len(binding) != 2 {
			return nil, &ExpansionError{Message: errMsg}
		}

		name, ok := binding[0].(symbol)
		if !ok {
			return nil, &ExpansionError{Message: errMsg}
		}

		names = append(names, name)
		values = append(values, binding[1])
	}

	lambda := listRaw{symbol("lambda"), names}
	lambda = append(lambda, args[1:]...)

	call := listRaw{lambda}
	call = append(call, values...)

	return call, nil
}

func expandAnd(args listRaw) any {
	if len(args) == 0 {
		return true
	}

	if len(args) == 1 {
		return true
	}

	rest := listRaw{symbol("and")}
	rest = append(rest, args[1:]...)

	// short circuit if it's false
	return listRaw{symbol("if"), args[0], rest, false}
}

func expandOr(args listRaw, depth int) any {
	if len(args) == 0 {
		return false
	}

	if len(args) == 1 {
		return args[0]
	}

	tmpSym := symbol("tmp#" + strconv.Itoa(depth))
	rest := listRaw{symbol("or")}
	rest = append(rest, args[1:]...)

	return listRaw{
		symbol("let"),
		listRaw{listRaw{tmpSym, args[0]}},
		listRaw{symbol("if"), tmpSym, tmpSym, rest},
	}
}
