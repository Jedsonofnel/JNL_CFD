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

type Closure struct {
	name   string
	arity  arity
	body   Sexp
	lexenv *env
	block  *Block
}

func (c Closure) Type() string { return "closure" }
func (c Closure) String() string {
	return "#<closure:" + c.name + " " + c.arity.String() + ">"
}

func (c Closure) Call(args []Sexp, f *fiber) (Sexp, Error) {
	var kwargs Map
	positionalArgs := args

	if len(args) > 0 {
		if m, ok := args[len(args)-1].(Map); ok && len(c.arity.keywords) > 0 {
			kwargs = m
			positionalArgs = args[:len(args)-1]
		}
	}

	argCount := len(positionalArgs)
	if argCount < c.arity.minArgs {
		return nil, f.newErrArityMin(c.name, c.arity.minArgs, argCount)
	}
	if c.arity.maxArgs != -1 && argCount > c.arity.maxArgs {
		return nil, f.newErrArityMax(c.name, c.arity.maxArgs, argCount)
	}

	activationEnv := newEnv(c.lexenv)

	// bind positional parameters
	for i, param := range c.arity.positional {
		activationEnv.bind(param, positionalArgs[i])
	}

	if c.arity.variadic != "" {
		variadicArgs := positionalArgs[len(c.arity.positional):]
		activationEnv.bind(c.arity.variadic, List{Elements: variadicArgs})
	}

	// bind named parameters from map
	for _, kw := range c.arity.keywords {
		value := kwargs.Get(kw)
		activationEnv.bind(kw, value)
	}

	f.block = c.block
	return f.eval(c.body, activationEnv)
}

// Foreign bindings

type Native struct {
	name string
	fn   func(args []Sexp, f *fiber) (Sexp, Error)
}

func (n Native) Type() string { return "native-function" }
func (n Native) String() string {
	return "#<native-function:" + n.name + ">"
}

func (n Native) Call(args []Sexp, f *fiber) (Sexp, Error) {
	return n.fn(args, f)
}

func NewNative(name string, fn func([]Sexp, *fiber) (Sexp, Error)) Native {
	return Native{name, fn}
}

func SimpleNative(name string, fn func([]Sexp) (Sexp, Error)) Native {
	return Native{
		name: name,
		fn: func(args []Sexp, _ *fiber) (Sexp, Error) {
			return fn(args)
		},
	}
}

type arity struct {
	positional []string
	variadic   string
	keywords   []string
	minArgs    int
	maxArgs    int
}

func (a arity) String() string {
	s := "["
	for _, p := range a.positional {
		s += string(p) + " "
	}
	if a.variadic != "" {
		s += "&var " + string(a.variadic) + " "
	}
	if len(a.keywords) > 0 {
		s += "&keys {"
		for _, k := range a.keywords {
			s += ":" + string(k) + " "
		}
		s += "}"
	}
	return s + "]"
}
