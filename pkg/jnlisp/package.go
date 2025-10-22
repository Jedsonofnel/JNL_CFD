package jnlisp

import (
	"io/fs"
)

type Package struct {
	Name     string
	FS       fs.FS
	Bindings map[string]Sexp
}

func (vm *VM) RegisterPackage(pkg Package) {
	vm.pkgRegistry[pkg.Name] = pkg
}

func (vm *VM) ImportPackage(name, prefix string) Error {
	// check it's in the library registry
	pkg, exists := vm.pkgRegistry[name]
	if !exists {
		// TODO: add filepath loading
		return RuntimeError{Message: "library not found: " + name}
	}

	_, found := vm.loadedPkgs[name]
	if !found {
		env, err := vm.executePackage(pkg)
		if err != nil {
			return RuntimeError{Message: "error executing package (" + name + "): " + err.Error()}
		}
		vm.loadedPkgs[name] = env
	}

	vm.loadedPkgs[name].forEachBinding(func(name string, sexp Sexp) {
		vm.importEnv.bind(prefix+name, sexp)
	})

	return nil
}

func (vm *VM) executePackage(pkg Package) (*env, Error) {
	pkgEnv := newEnv(vm.importEnv)

	for name, sexp := range pkg.Bindings {
		pkgEnv.bind(name, sexp)
	}

	return pkgEnv, nil

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
