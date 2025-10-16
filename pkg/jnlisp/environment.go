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

func newStandardEnv() (e *env) {
	e = newEnv(nil)
	return
}

// PROCEDURES

type ProcFunc func(args []Atom, kwargs TableAtom) (Atom, Error)

type paramList struct {
	positional []symbol
	named      []symbol
}

type Procedure struct {
	proc         ProcFunc
	name         string
	params       paramList
	body         expr
	closure      *env
	definingCtx  *Context
	importPrefix string
}

func (p *Procedure) Call(args []Atom, kwargs TableAtom, ctx *Context) (Atom, Error) {
	if p.proc != nil { // given a go binding
		return p.proc(args, kwargs)
	}

	activationEnv := newEnv(p.closure)

	if len(args) != len(p.params.positional) {
		return nil, RuntimeError{
			Message: p.name + " expects " +
				strconv.Itoa(len(p.params.positional)) +
				" positional args, got " + strconv.Itoa(len(args)),
		}
	}

	// bind positional parameters
	for i, param := range p.params.positional {
		activationEnv.bind(string(param), args[i])
	}

	// bind named parameters from table
	for _, namedParam := range p.params.named {
		paramName := string(namedParam)
		if value, exists := kwargs.Elements[paramName]; exists {
			activationEnv.bind(string(namedParam), value)
		} else {
			// TODO consider defaults later
			activationEnv.bind(string(namedParam), nil)
		}
	}

	if ctx == nil {
		ctx = p.definingCtx
	}

	callCtx := &Context{
		env:          activationEnv,
		importedLibs: ctx.importedLibs,
		importPrefix: p.importPrefix,
	}

	return eval(p.body, callCtx)
}
