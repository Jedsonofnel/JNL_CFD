package jnlisp

import (
	"io/fs"
)

type Package struct {
	Name     string
	FS       fs.FS
	Bindings map[string]NativeFunction
	Atoms    map[string]Atom
}

func (ctx *Context) RegisterPackage(pkg Package) {
	ctx.pkgRegistry[pkg.Name] = pkg
}

func (ctx *Context) ImportPackage(name, prefix string) Error {
	// check it's in the library registry
	pkg, exists := ctx.pkgRegistry[name]
	if !exists {
		// TODO: add filepath loading
		return RuntimeError{Message: "library not found: " + name}
	}

	_, found := ctx.loadedPkgs[name]
	if !found {
		env, err := ctx.executePackage(pkg)
		if err != nil {
			return RuntimeError{Message: "error executing package (" + name + "): " + err.Error()}
		}
		ctx.loadedPkgs[name] = env
	}

	ctx.loadedPkgs[name].forEachBinding(func(name string, atom Atom) {
		ctx.importEnv.bind(prefix+name, atom)
	})

	return nil
}

func (ctx *Context) executePackage(pkg Package) (*env, Error) {
	pkgEnv := newEnv(ctx.importEnv)

	fileContents, err := ctx.getFSSourceCode(pkg.FS)
	if err != nil {
		return nil, RuntimeError{
			Message: "Error reading package '" + pkg.Name + "' files: " + err.Error(),
		}
	}

	for i := range fileContents {
		tokens := tokenize(fileContents[i])
		blocks := parse(fileContents[i], tokens)
		blocks = ctx.executeWithEnv(blocks, pkgEnv)
		err := newBlockErrors(blocks)
		if err != nil {
			return nil, RuntimeError{
				Message: "Error executing package '" + pkg.Name + "': " + err.Error(),
			}
		}
	}

	// bind packages procedures
	for name, fn := range pkg.Bindings {
		pkgEnv.bind(name, &foreignFunction{name, fn})
	}
	for name, atom := range pkg.Atoms {
		pkgEnv.bind(name, atom)
	}

	return pkgEnv, nil
}
