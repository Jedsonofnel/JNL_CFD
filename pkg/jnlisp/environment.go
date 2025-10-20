package jnlisp

import (
	"strconv"
)

// ENV

type binding struct {
	name string
	sexp Sexp
}

type env struct {
	small [10]binding     // fast path for small closures
	large map[string]Sexp // Overflow
	outer *env
	size  int // number of bindings in small
}

func newEnv(outer *env) *env {
	return &env{
		large: make(map[string]Sexp),
		outer: outer,
	}
}

func (e *env) find(s string) (Sexp, bool) {
	// check small array first
	for i := range e.size {
		if e.small[i].name == s {
			return e.small[i].sexp, true
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

func (e *env) bind(s string, sexp Sexp) {
	if e.size < 10 {
		e.small[e.size] = binding{name: s, sexp: sexp}
		e.size++
	} else {
		e.large[s] = sexp
	}
}

func (e *env) forEachBinding(cb func(string, Sexp)) {
	// do small
	for i := range e.size {
		b := e.small[i]
		cb(b.name, b.sexp)
	}

	// do large
	for name, sexp := range e.large {
		cb(name, sexp)
	}
}

// Function bindings

type Function interface {
	Sexp
	Call(args []Sexp, kwargs Map, depth int) (Sexp, Error)
}

type fnParams struct {
	positional []Symbol
	named      []Symbol
}

type lispFunction struct {
	name    string
	params  fnParams
	body    expr
	closure *env
	vm      *VM
}

func (f *lispFunction) Type() string { return "function" }
func (f *lispFunction) String() string {
	return "#<function:" + f.name + ">"
}

func (f *lispFunction) Call(args []Sexp, kwargs Map, depth int) (Sexp, Error) {
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

	// bind named parameters from map
	for _, namedParam := range f.params.named {
		paramName := string(namedParam)
		if value, exists := kwargs[paramName]; exists {
			activationEnv.bind(string(namedParam), value)
		} else {
			// TODO consider defaults later
			activationEnv.bind(string(namedParam), nil)
		}
	}

	return f.vm.eval(f.body, activationEnv, depth)
}

// Foreign bindings

type NativeFunction func(args []Sexp, kwargs Map, depth int) (Sexp, Error)

func SimpleNative(fn func([]Sexp, Map) (Sexp, Error)) NativeFunction {
	return func(args []Sexp, kwargs Map, depth int) (Sexp, Error) {
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

func (f *foreignFunction) Call(args []Sexp, kwargs Map, depth int) (Sexp, Error) {
	return f.fn(args, kwargs, depth)
}
