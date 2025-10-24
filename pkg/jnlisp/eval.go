package jnlisp

func (f *fiber) eval(sexp Sexp, env *env) (Sexp, Error) {
	defer f.pop() // remove last frame from stack on return

	if len(f.stack) == 0 { // called top level without pushing to stack
		f.push(sexp, 0, opEval)
	}

	if f.recursionLimitReached() {
		return nil, f.newErrRecursionLimitReached()
	}

	f.push(sexp, 0, opExpand)
	sexp, err := f.expand(sexp, env)
	if err != nil {
		return nil, err
	}

	// ELABORATION
	f.push(sexp, 0, opElaborate)
	sexp, err = f.elaborate(sexp)
	if err != nil {
		return nil, err
	}

	// TCO LOOP
TCO:
	for {
		switch x := sexp.(type) {
		case Symbol:
			binding, exists := env.find(string(x))
			if !exists {
				return nil, f.newErrSymbolNotBound(string(x))
			}
			return binding, nil

		case defExpr:
			f.push(x, 2, opEval)
			binding, err := f.eval(x.binding, env)
			if err != nil {
				return nil, err
			}
			env.bind(x.name, binding)
			return binding, nil

		case List: // buckle up
			for i, elem := range x.Elements {
				f.push(x, i, opEval)
				evaledElem, err := f.eval(elem, env)
				if err != nil {
					return nil, err
				}
				x.Elements[i] = evaledElem
			}

			switch proc := x.First().(type) {
			case closure: // directly taken from the call but inlined for TCO
				var kwargs Map
				args := x.Elements[1:]

				if len(args) > 0 {
					if m, ok := args[len(args)-1].(Map); ok && len(proc.arity.Kwargs) > 0 {
						kwargs = m
						args = args[:len(args)-1]
					}
				}

				if !proc.arity.Matches(args) {
					return nil, f.newErrArity(proc.name, proc.arity, args)
				}

				activationEnv := newEnv(proc.lexenv)

				// bind positional parameters
				for i, param := range proc.arity.Positional {
					activationEnv.bind(param, args[i])
				}

				if proc.arity.Variadic != "" {
					variadicArgs := args[len(proc.arity.Variadic):]
					activationEnv.bind(proc.arity.Variadic, List{Elements: variadicArgs})
				}

				// bind named parameters from map
				for _, kw := range proc.arity.Kwargs {
					if value := kwargs.Get(kw.Name); value != nil {
						activationEnv.bind(kw.Name, value)
					} else {
						activationEnv.bind(kw.Name, kw.Default)
					}
				}
				sexp = proc.body
				env = proc.lexenv
				f.block = proc.block
				continue TCO
			case Callable:
				f.push(x, 0, opEval)
				return proc.Call(x.Elements[1:], f)
			default:
				return nil, f.newErrNonCallableCalled(proc.Type())
			}

		default:
			return x, nil
		}
	}
}
