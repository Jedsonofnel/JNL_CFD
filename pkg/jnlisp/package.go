package jnlisp

import (
	"io/fs"
)

type Package struct {
	Name     string
	FS       fs.FS
	Bindings map[string]Sexp

	env      *env
	location string
	src      []Document
}

func (rt *Runtime) loadPackage(name, prefix string, location *env) Error {
	// check it's in the library registry
	pkg, exists := rt.packages[name]
	if !exists {
		// TODO: add filepath loading
		return RuntimeError{Message: "library not found: " + name}
	}

	if pkg.env == nil {
		err := rt.executePackage(pkg)
		if err != nil {
			return RuntimeError{Message: "error executing package (" + name + "): " + err.Error()}
		}
	}

	for name, value := range pkg.env.bindings {
		location.bind(prefix+name, value)
	}

	return nil
}

func (rt *Runtime) executePackage(pkg *Package) Error {
	pkg.env = newEnv(rt.coreEnv)

	for name, sexp := range pkg.Bindings {
		pkg.env.bind(name, sexp)
	}

	return nil

	// fileContents, err := vm.getFSSourceCode(pkg.FS)
	// if err != nil {
	// 	return nil, RuntimeError{
	// 		Message: "Error reading package '" + pkg.Name + "' files: " + err.Error(),
	// 	}
	// }

	// for i := range fileContents {
	// 	// document := parse(fileContents[i])
	// 	// blocks = vm.executeWithEnv(blocks, pkgEnv)
	// 	// err := newBlockErrors(blocks)
	// 	// if err != nil {
	// 	// 	return nil, RuntimeError{
	// 	// 		Message: "Error executing package '" + pkg.Name + "': " + err.Error(),
	// 	// 	}
	// 	// }
	// }
}
