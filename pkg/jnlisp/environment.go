package jnlisp

import (
	"strings"
)

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

type CallableFunc func(args []Sexp, f *fiber) (Sexp, Error)

type Native struct {
	name  string
	arity *Arity // entirely for display, therefore nil-able
	fn    CallableFunc
}

func (n Native) Type() string { return "function" }
func (n Native) String() string {
	return "#<fn:" + n.name + " " + n.arity.String() + ">"
}

func (n Native) Call(args []Sexp, f *fiber) (Sexp, Error) {
	return n.fn(args, f)
}

func NewNative(name string, arity Arity, fn func([]Sexp, *fiber) (Sexp, Error)) Native {
	if name == "" {
		panic("cannot create Native with a name of the empty string")
	}

	return Native{name: name, arity: &arity, fn: fn}
}

type MultiArityNative struct {
	name    string
	arities MultiArity
	fns     []CallableFunc
}

func (n MultiArityNative) Type() string { return "function" }
func (n MultiArityNative) String() string {
	return "#<fn:" + n.name + " " + n.arities.String() + ">"
}

func (n MultiArityNative) Call(args []Sexp, f *fiber) (Sexp, Error) {
	for i := range n.arities {
		if n.arities[i].Matches(args) {
			// the panic on bad index is fine - it's a develoepr error
			return n.fns[i](args, f)
		}
	}

	return Nil{}, f.newErrMultiArity(n.name, n.arities, args)
}

func NewMultiArityNative(name string, arities MultiArity, fns []CallableFunc) MultiArityNative {
	if name == "" {
		panic("cannot create MultiArityNative with a name of the empty string")
	}

	if len(arities) == 0 {
		panic("cannot create MultiArityNative without at least one arity")
	}

	if len(arities) != len(fns) {
		panic("MultiArityNative must have as many arities as functions")
	}

	return MultiArityNative{name, arities, fns}
}

// represents the following [pos1 pos2 ...var {:kwarg default-value}]
type Arity struct {
	Positional []string
	Variadic   string
	Kwargs     []KwargDef
	original   Sexp
}

type KwargDef struct {
	Name    string
	Default Sexp
}

func (k KwargDef) String() string {
	return ":" + k.Name + " " + k.Default.String()
}

func (a Arity) Type() string { return "arity" }
func (a Arity) String() string {
	if a.original != nil {
		return a.original.String()
	}

	acc := strings.Builder{}
	acc.WriteString("[")

	acc.WriteString(strings.Join(a.Positional, " "))

	if a.Variadic != "" {
		acc.WriteString(" ...")
		acc.WriteString(a.Variadic)
	}

	for _, kw := range a.Kwargs {
		acc.WriteString(" ")
		acc.WriteString(kw.String())
	}

	acc.WriteString("]")
	return acc.String()
}

func (a Arity) MinArgs() int {
	return len(a.Positional)
}

func (a Arity) MaxArgs() int {
	if a.Variadic != "" {
		return -1
	}
	max := len(a.Positional)
	if len(a.Kwargs) > 0 {
		max++
	}
	return max
}

func (a Arity) AcceptsKwargs() bool {
	return len(a.Kwargs) > 0
}

func (a Arity) Matches(args []Sexp) bool {
	argCount := len(args)
	if a.MinArgs() > argCount {
		return false
	}

	maxArgs := a.MaxArgs()
	if maxArgs < argCount && maxArgs >= 0 { // too many args
		return false
	}

	// if more than positional and kwargs requried, last arg must be map
	if a.AcceptsKwargs() && argCount > len(a.Positional) {
		if _, ok := args[argCount-1].(Map); !ok {
			return false
		}
	}

	return true
}

// for multi arity matching
// TODO: add sorting and uniqueness check
type MultiArity []Arity

func (ma MultiArity) Type() string { return "arity" }
func (ma MultiArity) String() string {
	acc := strings.Builder{}
	acc.WriteString("[")

	arityStrings := make([]string, 0, len(ma))
	for i := range len(ma) {
		arityStrings = append(arityStrings, ma[i].String())
	}
	acc.WriteString(strings.Join(arityStrings, " "))

	acc.WriteString("]")
	return acc.String()
}
