package jnlisp

func (f *fiber) expand(sexp Sexp, env *env) (Sexp, Error) {
	if f.recursionLimitReached() {
		return nil, f.newErrRecursionLimitReached()
	}
	defer f.pop() // remove frame from stack after this

	switch s := sexp.(type) {
	case List:
		if s.Length() == 0 {
			return s, nil
		}

		// lookup in macro table (TODO - no such table exists, manually does essentials (defn, or, and, let) for now)
		if expanded, err, ok := f.callMacro(s, env); ok {
			if err != nil {
				return nil, err
			}
			f.pushExpand(s, -1)
			return f.expand(expanded, env)
		}

		// not a macro - expand children
		for i, child := range s.Elements {
			f.pushExpand(s, i)
			expanded, err := f.expand(child, env)
			if err != nil {
				return nil, err
			}
			s.Elements[i] = expanded
		}
		return s, nil
	case Vector:
		for i, child := range s.Elements {
			f.pushExpand(child, i)
			expanded, err := f.expand(child, env)
			if err != nil {
				return nil, err
			}
			s.Elements[i] = expanded
		}
		return s, nil
	case Map:
		for key, value := range s.Elements {
			f.pushExpandMapValue(value, key) // THIS IS WRONG - need to have a separate field for mapkey
			expanded, err := f.expand(value, env)
			if err != nil {
				return nil, err
			}
			s.Elements[key] = expanded
		}
		return s, nil
	default:
		return sexp, nil // most types don't need expansion
	}
}

func (f *fiber) callMacro(list List, env *env) (Sexp, Error, bool) {
	if sym, ok := list.First().(Symbol); ok {
		switch string(sym) {
		case "defn":
			expanded, err := expandDefn(list, f)
			return expanded, err, true
		case "let":
			expanded, err := expandLet(list, f)
			return expanded, err, true
		case "and":
			expanded := expandAnd(list)
			return expanded, nil, true
		case "or":
			expanded := expandOr(list, f)
			return expanded, nil, true
		}
	}

	return nil, nil, false
}

// BUILT IN EXPANSIONS (should eventually be superseded by macros)

// expand (defn sym [args...] body...) to (def sym (fn [args...] body...))
func expandDefn(list List, f *fiber) (Sexp, Error) {
	if list.Length() < 4 {
		return nil, f.newErrMacroArityMinimum("defn", 3, list.Length()-1)
	}

	// assume first element is "defn"

	name, ok := list.Elements[1].(Symbol)
	if !ok {
		return nil, f.newErrMacroArgType("defn", "symbol", 1)
	}

	params, ok := list.Elements[2].(Vector)
	if !ok {
		return nil, f.newErrMacroArgType("defn", "vector", 2)
	}

	fnElems := []Sexp{Symbol("fn"), params}
	fnElems = append(fnElems, list.Elements[3:]...)

	fn := List{Elements: fnElems}
	def := List{
		Elements: []Sexp{Symbol("def"), name, fn},
		meta:     list.meta,
	}

	return def, nil
}

// expand (let [s1 b1 s2 b2] body...) to ((fn [s1 s2] body...) b1 b2)
func expandLet(list List, f *fiber) (Sexp, Error) {
	if list.Length() < 3 {
		return nil, f.newErrMacroArity("let", 3, list.Length()-1)
	}

	bindings, ok := list.Elements[1].(Vector)
	if !ok {
		return nil, f.newErrMacroArgType("let", "vector", 1)
	}

	var fnParams, fnArgs []Sexp

	if len(bindings.Elements)%2 != 0 {
		return nil, ExpansionError{
			Code:    ErrMacroInvalidForm,
			Message: "let bindings must have even number of forms (symbol/value pairs)",
			stack:   f.copyStack(),
		}
	}

	for i := range bindings.Elements {
		if i%2 == 0 {
			fnParams = append(fnParams, bindings.Elements[i])
		} else {
			fnArgs = append(fnArgs, bindings.Elements[i])
		}
	}

	fnParamVec := Vector{Elements: fnParams}
	fnElems := []Sexp{Symbol("fn"), fnParamVec}
	fnElems = append(fnElems, list.Elements[2:]...)
	fn := List{Elements: fnElems}

	call := List{Elements: []Sexp{fn}}
	call.Elements = append(call.Elements, fnArgs...)

	return call, nil
}

func expandAnd(list List) Sexp {
	if list.Length() == 1 {
		return Boolean(true)
	}

	if list.Length() == 2 {
		return list.Elements[1]
	}

	rest := List{Elements: []Sexp{Symbol("and")}}
	rest.Elements = append(rest.Elements, list.Elements[2:]...)

	// short circuit if it's false
	return List{
		Elements: []Sexp{Symbol("if"), list.Elements[1], rest, Boolean(false)},
	}
}

// expand (or a b) to (let [tmp a] (if tmp tmp (or b)))
func expandOr(list List, f *fiber) Sexp {
	if list.Length() == 1 {
		return Boolean(false)
	}

	if list.Length() == 2 {
		return list.Elements[1]
	}

	tmpSym := f.gensym()
	rest := List{Elements: []Sexp{Symbol("or")}}
	rest.Elements = append(rest.Elements, list.Elements[2:]...)

	ifElems := []Sexp{Symbol("if"), tmpSym, tmpSym, rest}
	ifSexp := List{Elements: ifElems}

	orElems := []Sexp{
		Symbol("let"),
		Vector{Elements: []Sexp{tmpSym, list.Elements[1]}},
		ifSexp,
	}

	return List{Elements: orElems}
}
