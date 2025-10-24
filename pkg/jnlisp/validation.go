package jnlisp

type ArgValidator struct {
	args  []Sexp
	arity Arity
	fiber *fiber
	name  string

	kwargs Map
	idx    int
	error  Error
}

func ValidateArgs(args []Sexp, arity Arity, f *fiber, name string) *ArgValidator {
	av := &ArgValidator{
		args:  args,
		arity: arity,
		fiber: f,
		name:  name,
		idx:   -1,
	}

	if !arity.Matches(args) {
		av.error = f.newErrArity(name, arity, args)
		return av
	}

	// figure out if kwargs expected from arity and attach to av if present
	numArgs := len(args)
	if numArgs > len(arity.Positional) && arity.AcceptsKwargs() {
		if kwargs, exists := args[numArgs-1].(Map); exists {
			av.kwargs = kwargs
			av.args = args[:numArgs-1]
		}
	}

	return av
}

func (av *ArgValidator) Validate() Error {
	if av.error != nil {
		return av.error
	}

	for _, key := range av.kwargs.order {
		found := false
		for _, kw := range av.arity.Kwargs {
			if kw.Name == key {
				found = true
				break
			}
		}
		if !found {
			return av.fiber.newErrUnexpectedKwarg(av.name, key)
		}
	}

	return nil
}

// wrapper for concrete Sexp types
func GetArg[T Sexp](av *ArgValidator) T {
	var zero T
	return GetInterfaceArg[T](av, zero.Type())
}

// for when T is an interface type so you can't call Sexp methods to get Type() for instance
func GetInterfaceArg[T Sexp](av *ArgValidator, typeName string) T {
	var zero T
	if av.error != nil {
		return zero
	}

	av.idx++
	arg := av.args[av.idx]

	if sexp, ok := arg.(T); ok {
		return sexp
	}

	av.error = av.fiber.newErrPosArgType(av.name, typeName, arg.Type(), av.idx+1)
	return zero
}

func GetVariadic[T Sexp](av *ArgValidator) []T {
	var zero T
	return GetInterfaceVariadic[T](av, zero.Type())
}

func GetInterfaceVariadic[T Sexp](av *ArgValidator, typeName string) []T {
	zero := make([]T, 0, len(av.args)-av.idx)
	if av.error != nil {
		return zero
	}

	av.idx++

	for i := av.idx; i < len(av.args); i++ {
		if sexp, ok := av.args[i].(T); ok {
			zero = append(zero, sexp)
		} else {
			av.error = av.fiber.newErrVariadicArgType(av.name, typeName, av.args[i].Type(), i)
			return zero
		}
	}

	return zero
}

func GetKwarg[T Sexp](av *ArgValidator, key string) T {
	var zero T
	return GetInterfaceKwarg[T](av, key, zero.Type())
}

func GetInterfaceKwarg[T Sexp](av *ArgValidator, key, typeName string) T {
	var zero T
	if av.error != nil {
		return zero
	}

	if provided := av.kwargs.Get(key); provided != (Nil{}) {
		if value, ok := provided.(T); ok {
			return value
		} else {
			av.error = av.fiber.newErrKwargType(av.name, key, typeName, provided.Type())
			return zero
		}
	}

	for _, kwarg := range av.arity.Kwargs {
		if def, ok := kwarg.Default.(T); key == kwarg.Name && ok {
			return def
		}
	}

	return zero
}
