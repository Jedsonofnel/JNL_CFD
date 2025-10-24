package jnlisp

import (
	"io/fs"
)

type Runtime struct {
	coreEnv  *env
	replEnv  *env
	packages map[string]*Package
}

func NewRuntime() *Runtime {
	coreEnv := newEnv(nil)
	replEnv := newEnv(coreEnv)

	rt := &Runtime{
		coreEnv:  coreEnv,
		replEnv:  replEnv,
		packages: make(map[string]*Package),
	}

	rt.RegisterPackage(corePkg)
	if err := rt.loadPackage("core", "", coreEnv); err != nil {
		panic("Error importing package core: " + err.Error())
	}

	return rt
}

func (rt *Runtime) RegisterPackage(pkg *Package) {
	rt.packages[pkg.Name] = pkg
}

// TODO: main entrypoint publicly for running files
func (rt *Runtime) Eval(_ fs.FS, _ string) []Block {
	return nil
}

// func (ctx *Context) bindIt(blocks []Block) {
// 	if len(blocks) == 0 {
// 		return
// 	}
//
// 	last := blocks[len(blocks)-1]
// 	if len(last.Errors) > 0 || last.Result == nil {
// 		return
// 	}
//
// 	ctx.userEnv.bind("it", last.Result)
// }

// allows for specific environment for usage with package importing
// func (ctx *Context) executeWithEnv(blocks []Block, env *env) []Block {
// 	var codeBlocks []Block
// 	for i := range blocks {
// 		b := blocks[i]
// 		if b.Type != "code" || len(b.Errors) > 0 {
// 			continue
// 		}
//
// 		codeBlocks = append(codeBlocks, b)
// 		block := &codeBlocks[len(codeBlocks)-1]
//
// 		expandedAST, err := expand(block.rawAST, 0)
// 		if err != nil {
// 			block.Errors = append(block.Errors, err)
// 			continue
// 		}
//
// 		elaboratedAST, err := elaborate(expandedAST)
// 		if err != nil {
// 			block.Errors = append(block.Errors, err)
// 			continue
// 		}
//
// 		result, err := ctx.eval(elaboratedAST, env, 0)
// 		if result != nil {
// 			block.Result = result
// 		}
// 		if err != nil {
// 			block.Errors = append(block.Errors, err)
// 		}
// 	}
//
// 	return codeBlocks
// }

// func (vm *VM) getFSSourceCode(fsys fs.FS) ([]string, Error) {
// 	var fileContents []string
//
// 	err := fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
// 		if err != nil {
// 			return newFSError(path, "walk", err)
// 		}
//
// 		if d.IsDir() || !strings.HasSuffix(path, ".jnl") {
// 			return nil
// 		}
//
// 		content, err := fs.ReadFile(fsys, path)
// 		if err != nil {
// 			return newFSError(path, "read", err)
// 		}
// 		fileContents = append(fileContents, string(content))
// 		return nil
// 	})
//
// 	if err != nil {
// 		return nil, err.(FileSystemError)
// 	}
//
// 	return fileContents, nil
// }
