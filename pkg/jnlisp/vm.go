package jnlisp

import (
	"io/fs"
	"strconv"
	"strings"
)

type VM struct {
	userEnv   *env
	importEnv *env

	pkgRegistry map[string]Package
	loadedPkgs  map[string]*env

	replBuf  strings.Builder
	replLine int
}

func NewVM() *VM {
	importEnv := newEnv(nil)
	userEnv := newEnv(importEnv)

	vm := &VM{
		importEnv:   importEnv,
		userEnv:     userEnv,
		pkgRegistry: make(map[string]Package),
		loadedPkgs:  make(map[string]*env),
		replBuf:     strings.Builder{},
		replLine:    0,
	}

	vm.RegisterPackage(corePkg)

	err := vm.ImportPackage("core", "")
	if err != nil {
		panic("Error importing package core: " + err.Error())
	}
	return vm
}

func (vm *VM) Reset() {
	vm.importEnv = newEnv(nil)
	vm.userEnv = newEnv(vm.importEnv)
	vm.replBuf.Reset()
	vm.replLine = 0
}

func (vm *VM) ReplPrompt(missingDelims string) string {
	vm.replLine++
	prompt := "jnlisp:" + strconv.Itoa(vm.replLine) + ":" + missingDelims + "> "
	return prompt
}

// EXECUTION
// can be in a step() for a REPL or execute() for all in one go

func (vm *VM) Step(input string) (Document, string) {
	vm.replBuf.WriteString(input)
	document := parse(vm.replBuf.String())

	if len(document) == 0 {
		vm.replBuf.Reset()
		return nil, ""
	}

	missingDelims := ""
	lastBlock := document[len(document)-1]
	for _, err := range lastBlock.Errors {
		if missing, ok := err.(missingDelim); ok {
			missingDelims += missing.matching()
		} else {
			vm.replBuf.Reset()
			return document, "" // ie blocking error detected
		}
	}

	if missingDelims != "" {
		return nil, missingDelims
	}

	vm.replBuf.Reset()
	return document, ""
}

func (vm *VM) Execute(input string) []Block {
	document := parse(input)
	// TODO: re-figure out eval
	return document
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

func (vm *VM) getFSSourceCode(fsys fs.FS) ([]string, Error) {
	var fileContents []string

	err := fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return newFSError(path, "walk", err)
		}

		if d.IsDir() || !strings.HasSuffix(path, ".jnl") {
			return nil
		}

		content, err := fs.ReadFile(fsys, path)
		if err != nil {
			return newFSError(path, "read", err)
		}
		fileContents = append(fileContents, string(content))
		return nil
	})

	if err != nil {
		return nil, err.(FileSystemError)
	}

	return fileContents, nil
}
