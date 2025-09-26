package jnlisp

import (
	"fmt"
)

// ENV

type env struct {
	bindings map[string]Atom
	outer    *env
}

func newEnv(outer *env) *env {
	return &env{
		bindings: make(map[string]Atom),
		outer:    outer,
	}
}

func (e *env) find(s string) (Atom, bool) {
	if val, exists := e.bindings[s]; exists {
		return val, true
	}

	if e.outer != nil {
		return e.outer.find(s)
	}

	return nil, false
}

func (e *env) bind(s string, atom Atom) boundAtom {
	boundAtom := boundAtom{
		Atom:   atom,
		handle: s,
		env:    e,
	}
	e.bindings[s] = boundAtom
	return boundAtom
}

func newStandardEnv() (e *env) {
	e = newEnv(nil)
	return
}

type Table map[string]Atom // TODO: move this to parser when I add a vector type etc

// PROCEDURES

type ProcFunc func(args []Atom, kwargs Table) (Atom, error)

type paramList struct {
	positional []symbol
	named      []symbol
}

type Procedure struct {
	proc         ProcFunc
	name         string
	params       paramList
	body         []any
	closure      *env
	importPrefix string
}

func (p *Procedure) Call(args []Atom, kwargs Table, ctx *Context) (Atom, error) {
	if p.proc != nil { // given a go binding
		return p.proc(args, kwargs)
	}

	activationEnv := newEnv(p.closure)

	if len(args) != len(p.params.positional) {
		return nil, fmt.Errorf("'%s' expects %d positional args, got %d",
			p.name, len(p.params.positional), len(args))
	}

	// bind positional parameters
	for i, param := range p.params.positional {
		activationEnv.bind(string(param), args[i])
	}

	// bind named parameters from table
	for _, namedParam := range p.params.named {
		paramName := string(namedParam)
		if value, exists := kwargs[paramName]; exists {
			activationEnv.bind(string(namedParam), value)
		} else {
			// TODO consider defaults later
			activationEnv.bind(string(namedParam), nil)
		}
	}

	callCtx := &Context{
		env:          activationEnv,
		importedLibs: ctx.importedLibs,
		importPrefix: p.importPrefix,
	}

	var result Atom
	var err error
	for _, expr := range p.body {
		result, err = eval(expr, callCtx)
		if err != nil {
			return nil, err
		}
	}

	return result, err
}
