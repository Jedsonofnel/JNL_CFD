package jnlisp

import (
	"io/fs"
)

type Package struct {
	Name     string
	FS       fs.FS
	Bindings map[string]NativeFunction
	Sexps    map[string]Sexp
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

	ctx.loadedPkgs[name].forEachBinding(func(name string, sexp Sexp) {
		ctx.importEnv.bind(prefix+name, sexp)
	})

	return nil
}

func (ctx *Context) executePackage(pkg Package) (*env, Error) {
	pkgEnv := newEnv(ctx.importEnv)

	// bind packages procedures
	for name, fn := range pkg.Bindings {
		pkgEnv.bind(name, &foreignFunction{name, fn})
	}
	for name, sexp := range pkg.Sexps {
		pkgEnv.bind(name, sexp)
	}

	return pkgEnv, nil

	// fileContents, err := ctx.getFSSourceCode(pkg.FS)
	// if err != nil {
	// 	return nil, RuntimeError{
	// 		Message: "Error reading package '" + pkg.Name + "' files: " + err.Error(),
	// 	}
	// }

	// for i := range fileContents {
	// 	// document := parse(fileContents[i])
	// 	// blocks = ctx.executeWithEnv(blocks, pkgEnv)
	// 	// err := newBlockErrors(blocks)
	// 	// if err != nil {
	// 	// 	return nil, RuntimeError{
	// 	// 		Message: "Error executing package '" + pkg.Name + "': " + err.Error(),
	// 	// 	}
	// 	// }
	// }
}
