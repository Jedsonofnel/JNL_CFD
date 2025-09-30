package jnlisp

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"strings"
	"sync"
)

// GLOBAL LIBRARY REGISTRY

var libraryRegistry = make(map[string]Library)
var registryMutex sync.RWMutex

type Library struct {
	Name     string
	Src      embed.FS
	Bindings map[string]ProcFunc
	Atoms    map[string]Atom
}

func RegisterLibrary(lib Library) error {
	registryMutex.Lock()
	defer registryMutex.Unlock()

	if _, exists := libraryRegistry[lib.Name]; exists {
		return fmt.Errorf("library with name '%s' already exists", lib.Name)
	}

	libraryRegistry[lib.Name] = lib

	return nil
}

// CONTEXTS

type Context struct {
	env          *env
	importedLibs map[string]bool
	importPrefix string
}

func NewContext() *Context {
	ctx := &Context{
		env:          newStandardEnv(),
		importedLibs: make(map[string]bool),
	}
	ctx.ImportLibrary("core", "")

	return ctx
}

func (c *Context) Extend() *Context {
	localCtx := &Context{
		env:          newEnv(c.env),
		importedLibs: c.importedLibs,
	}

	return localCtx
}

func (c *Context) ImportLibrary(name, prefix string) error {
	if c.importedLibs[name] {
		return nil // already imported
	}

	registryMutex.RLock()
	lib, exists := libraryRegistry[name]
	registryMutex.RUnlock()

	if !exists {
		return fmt.Errorf("library not found: %s", name)
	}

	// bind library's procedures with prefix
	for procName, procFunc := range lib.Bindings {
		bindName := procName
		if prefix != "" {
			bindName = prefix + "/" + procName
		}
		c.BindProcedure(bindName, procFunc)
	}

	for atomName, atom := range lib.Atoms {
		bindName := atomName
		if prefix != "" {
			bindName = prefix + "/" + atomName
		}
		c.BindAtom(bindName, atom)
	}

	oldPrefix := c.importPrefix
	c.importPrefix = prefix
	defer func() {
		c.importPrefix = oldPrefix
	}()

	// execute library source in SAME environment
	err := c.evaluateEmbeddedSrc(lib.Src)
	if err != nil {
		return err
	}

	c.importedLibs[name] = true
	return nil
}

func (c *Context) BindProcedure(name string, proc ProcFunc) {
	c.env.bind(name, ProcedureAtom{&Procedure{
		proc: proc,
		name: name,
	}})
}

func (c *Context) BindAtom(name string, atom Atom) {
	c.env.bind(name, atom)
}

func (c *Context) Reset() {
	c.env = newStandardEnv()
}

type Block struct {
	StartPos Pos                `json:"startPos"`
	EndPos   Pos                `json:"endPos"`
	Result   map[string]any     `json:"result"`
	Errors   []InterpreterError `json:"errors"`
}

func (c *Context) LoadFromString(source string) ([]Block, error) {
	return c.evaluateSrc(source)
}

func (c *Context) LoadFromFile(contents string) ([]Block, error) {
	content, err := os.ReadFile(contents)
	if err != nil {
		return nil, err
	}
	return c.evaluateSrc(string(content))
}

type InterpreterError struct {
	Pos     Pos    `json:"position"`
	Message string `json:"message"`
}

// IMPLEMENTATION

func (c *Context) evaluateSrc(src string) ([]Block, error) {
	var blocks []Block

	tokens := tokenizeSrc(src)
	parsedResults, positions := parseSrc(tokens)

	for i, parsedResult := range parsedResults {
		b := Block{
			StartPos: positions[i].startPos,
			EndPos:   positions[i].endPos,
		}

		isSyntaxError := false
		for _, err := range parsedResult.Errors {
			isSyntaxError = true
			b.Errors = append(b.Errors, InterpreterError{err.token.pos, err.Error()})
		}

		if isSyntaxError {
			blocks = append(blocks, b)
			continue
		}

		result, err := eval(parsedResult.Expr, c)
		if result != nil {
			b.Result = result.ToJSON()
		}

		if err != nil {
			// line -1 means no position specified
			b.Errors = append(b.Errors, InterpreterError{Pos{Line: -1}, err.Error()})
		}

		blocks = append(blocks, b)
	}

	return blocks, nil
}

func (c *Context) evaluateEmbeddedSrc(fsys embed.FS) error {
	return fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if d.IsDir() || !strings.HasSuffix(path, ".jnl") {
			return nil
		}

		content, err := fs.ReadFile(fsys, path)
		if err != nil {
			return fmt.Errorf("failed to read %s: %w", path, err)
		}

		_, err = c.evaluateSrc(string(content))
		if err != nil {
			return fmt.Errorf("error in %s: %w", path, err)
		}

		return nil
	})
}
