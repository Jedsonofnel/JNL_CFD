package jnlisp

func (f *fiber) eval(sexp Sexp, idx int, env *env) (Sexp, Error) {
	f.push(sexp, idx, opEval)
	defer f.pop() // remove last frame from stack on return

	if f.recursionLimitReached() {
		return Nil{}, f.newErrRecursionLimitReached()
	}

	sexp, err := f.expand(sexp, 0, env)
	if err != nil {
		return Nil{}, err
	}

	// ELABORATION
	sexp, err = f.elaborate(sexp, 0)
	if err != nil {
		return Nil{}, err
	}

	// TCO LOOP
TCO:
	for {
		switch x := sexp.(type) {
		case Symbol:
			binding, exists := env.find(string(x))
			if !exists {
				return Nil{}, f.newErrSymbolNotBound(string(x))
			}
			return binding, nil

		case defExpr:
			binding, err := f.eval(x.binding, 2, env)
			if err != nil {
				return Nil{}, err
			}

			if closure, ok := binding.(closure); ok {
				closure.name = x.name
				binding = closure
			}

			env.bind(x.name, binding)
			return binding, nil

		case fnExpr:
			closure := closure{
				arity:  x.arity,
				body:   x.body,
				last:   x.last,
				lexenv: env,
				block:  f.block,
			}
			return closure, nil

		case ifExpr:
			pred, err := f.eval(x.predicate, 1, env)
			if err != nil {
				return Nil{}, err
			}

			switch pred := pred.(type) {
			case Nil:
				sexp = x.alternative
				continue TCO
			case Boolean:
				if bool(pred) {
					sexp = x.conseq
					continue TCO
				} else { // false
					sexp = x.alternative
					continue TCO
				}
			default:
				sexp = x.conseq
				continue TCO
			}

		case doExpr:
			env = newEnv(env) // start a new closure
			for i, exp := range x.body {
				_, err := f.eval(exp, i+1, env)
				if err != nil {
					return Nil{}, err
				}
			}
			sexp = x.last
			continue TCO

		case quoteExpr:
			return x.sexp, nil

		case List: // buckle up
			for i, elem := range x.Elements {
				evaledElem, err := f.eval(elem, i, env)
				if err != nil {
					return Nil{}, err
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
					return Nil{}, f.newErrArity(proc.name, proc.arity, args)
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

				f.block = proc.block
				env = activationEnv

				for i, expr := range proc.body {
					_, err := f.eval(expr, i+2, env)
					if err != nil {
						return Nil{}, err
					}
				}

				f.updateCurrentFrame(proc.last, 0)
				sexp = proc.last
				continue TCO
			case Callable:
				return proc.Call(x.Elements[1:], f)
			default:
				return Nil{}, f.newErrNonCallableCalled(proc.Type())
			}

		default: // literals evaluate to themselves
			return x, nil
		}
	}
}
