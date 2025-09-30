package jnlisp

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"strings"
	"sync"
)

// DOCUMENT BLOCKS FOR CONSUMPTION

type Block struct {
	// Lexer/parser metadata
	Type     string `json:"type"` // "prose" | "code"
	Content  string `json:"content"`
	StartPos Pos    `json:"startPos"`
	EndPos   Pos    `json:"endPos"`

	// OPTIONAL: If evaluated
	Result map[string]any `json:"result,omitempty"`

	// SyntaxErrors (parser) or RuntimeErrors (evaluator)
	Errors []InterpreterError `json:"errors,omitempty"`

	// OPTIONAL: If code block - the parsed expression AST
	exp any
}

type InterpreterError struct {
	Pos     Pos    `json:"position"`
	Message string `json:"message"`
}

// CONTEXT TO MANAGE ENV

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

// GLOBAL LIBRARY REGISTRY

var libraryRegistry = make(map[string]Library)
var registryMutex sync.RWMutex

type Library struct {
	Name     string
	FS       embed.FS
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

// OTHER METHODS

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

// PARSING (for syntax highlighting etc)

func ParseBytes(bytes []byte) []Block {
	tokens := tokenizeDocument(string(bytes))
	return parseDocument(string(bytes), tokens)
}

// EVALUATING

func (c *Context) EvalString(source string) []Block {
	return c.evalDocument(source)
}

func (c *Context) EvalBytes(bytes []byte) []Block {
	return c.evalDocument(string(bytes))
}

func (c *Context) EvalFile(contents string) ([]Block, error) {
	content, err := os.ReadFile(contents)
	if err != nil {
		return nil, err
	}
	return c.evalDocument(string(content)), nil
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
	err := c.evalEmbeddedDocuments(lib.FS)
	if err != nil {
		return err
	}

	c.importedLibs[name] = true
	return nil
}

// IMPLEMENTATION

func (c *Context) evalDocument(src string) []Block {
	tokens := tokenizeDocument(src)
	blocks := parseDocument(src, tokens)

	for i := range blocks {
		if blocks[i].Type != "code" || len(blocks[i].Errors) > 0 {
			continue
		}

		result, err := eval(blocks[i].exp, c)

		if result != nil {
			blocks[i].Result = result.ToJSON()
		}
		if err != nil {
			blocks[i].Errors = append(blocks[i].Errors, InterpreterError{Pos{Line: -1}, err.Error()})
		}
	}

	return blocks
}

func (c *Context) evalEmbeddedDocuments(fsys embed.FS) error {
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

		_ = c.evalDocument(string(content))

		return nil
	})
}
