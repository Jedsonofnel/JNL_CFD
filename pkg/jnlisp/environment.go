package jnlisp

type env struct {
	bindings map[string]Sexp // Overflow
	outer    *env
}

func newEnv(outer *env) *env {
	return &env{
		bindings: make(map[string]Sexp),
		outer:    outer,
	}
}

func (e *env) find(s string) (Sexp, bool) {
	if val, exists := e.bindings[s]; exists {
		return val, true
	}

	if e.outer != nil {
		return e.outer.find(s)
	}

	return nil, false
}

func (e *env) bind(s string, sexp Sexp) {
	e.bindings[s] = sexp
}

type Callable interface {
	Sexp
	Call(args []Sexp, fiber *fiber) (Sexp, Error)
}

type closure struct {
	name   string
	arity  Arity
	body   Sexp
	lexenv *env
	block  *Block
}

func (c closure) Type() string { return "function" }
func (c closure) String() string {
	return "#<fn:" + c.name + " " + c.arity.String() + ">"
}

func (c closure) Call(args []Sexp, f *fiber) (Sexp, Error) {
	var kwargs Map
	positionalArgs := args

	if len(args) > 0 {
		if m, ok := args[len(args)-1].(Map); ok && len(c.arity.Kwargs) > 0 {
			kwargs = m
			positionalArgs = args[:len(args)-1]
		}
	}

	if !c.arity.Matches(args) {
		return nil, f.newErrArity(c.name, c.arity, args)
	}

	activationEnv := newEnv(c.lexenv)

	// bind positional parameters
	for i, param := range c.arity.Positional {
		activationEnv.bind(param, positionalArgs[i])
	}

	if c.arity.Variadic != "" {
		variadicArgs := positionalArgs[len(c.arity.Variadic):]
		activationEnv.bind(c.arity.Variadic, List{Elements: variadicArgs})
	}

	// bind named parameters from map
	for _, kw := range c.arity.Kwargs {
		if value := kwargs.Get(kw.Name); value != nil {
			activationEnv.bind(kw.Name, value)
		} else {
			activationEnv.bind(kw.Name, kw.Default)
		}
	}

	f.block = c.block
	return f.eval(c.body, 0, activationEnv)
}

// Foreign bindings

type Native struct {
	name  string
	arity *Arity // nil means don't check
	fn    func(args []Sexp, f *fiber) (Sexp, Error)
}

func (n Native) Type() string { return "native-function" }
func (n Native) String() string {
	return "#<fn:" + n.name + ">"
}

func (n Native) Call(args []Sexp, f *fiber) (Sexp, Error) {
	if n.arity != nil && !n.arity.Matches(args) {
		return nil, f.newErrArity(n.name, *n.arity, args)
	}
	return n.fn(args, f)
}

func NewNative(name string, fn func([]Sexp, *fiber) (Sexp, Error)) Native {
	return Native{name: name, fn: fn}
}

func SimpleNative(name string, fn func([]Sexp) (Sexp, Error)) Native {
	return Native{
		name: name,
		fn: func(args []Sexp, _ *fiber) (Sexp, Error) {
			return fn(args)
		},
	}
}
