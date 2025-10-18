package jnlisp

import (
	"strconv"
)

// ENV

type binding struct {
	name string
	atom Atom
}

type env struct {
	small [10]binding     // fast path for small closures
	large map[string]Atom // Overflow
	outer *env
	size  int // number of bindings in small
}

func newEnv(outer *env) *env {
	return &env{
		large: make(map[string]Atom),
		outer: outer,
	}
}

func (e *env) find(s string) (Atom, bool) {
	// check small array first
	for i := range e.size {
		if e.small[i].name == s {
			return e.small[i].atom, true
		}
	}

	if val, exists := e.large[s]; exists {
		return val, true
	}

	if e.outer != nil {
		return e.outer.find(s)
	}

	return nil, false
}

func (e *env) bind(s string, atom Atom) {
	if e.size < 10 {
		e.small[e.size] = binding{name: s, atom: atom}
		e.size++
	} else {
		e.large[s] = atom
	}
}

func (e *env) forEachBinding(cb func(string, Atom)) {
	// do small
	for i := range e.size {
		b := e.small[i]
		cb(b.name, b.atom)
	}

	// do large
	for name, atom := range e.large {
		cb(name, atom)
	}
}

// Function bindings

type Function interface {
	Atom
	Call(args []Atom, kwargs TableAtom, depth int) (Atom, Error)
}

type fnParams struct {
	positional []symbol
	named      []symbol
}

type lispFunction struct {
	name    string
	params  fnParams
	body    expr
	closure *env
	ctx     *Context
}

func (f *lispFunction) Type() string { return "function" }
func (f *lispFunction) String() string {
	return "#<function:" + f.name + ">"
}

func (f *lispFunction) Call(args []Atom, kwargs TableAtom, depth int) (Atom, Error) {
	activationEnv := newEnv(f.closure)

	if len(args) != len(f.params.positional) {
		return nil, RuntimeError{
			Message: f.name + " expects " +
				strconv.Itoa(len(f.params.positional)) +
				" positional args, got " + strconv.Itoa(len(args)),
		}
	}

	// bind positional parameters
	for i, param := range f.params.positional {
		activationEnv.bind(string(param), args[i])
	}

	// bind named parameters from table
	for _, namedParam := range f.params.named {
		paramName := string(namedParam)
		if value, exists := kwargs[paramName]; exists {
			activationEnv.bind(string(namedParam), value)
		} else {
			// TODO consider defaults later
			activationEnv.bind(string(namedParam), nil)
		}
	}

	return f.ctx.eval(f.body, activationEnv, depth)
}

// Foreign bindings

type NativeFunction func(args []Atom, kwargs TableAtom, depth int) (Atom, Error)

func SimpleNative(fn func([]Atom, TableAtom) (Atom, Error)) NativeFunction {
	return func(args []Atom, kwargs TableAtom, depth int) (Atom, Error) {
		return fn(args, kwargs)
	}
}

type foreignFunction struct {
	name string
	fn   NativeFunction
}

func (f *foreignFunction) Type() string { return "function" }
func (f *foreignFunction) String() string {
	return "#<function:" + f.name + ">"
}

func (f *foreignFunction) Call(args []Atom, kwargs TableAtom, depth int) (Atom, Error) {
	return f.fn(args, kwargs, depth)
}
