package jnlisp

import (
	"io/fs"
	"strconv"
	"strings"
)

// DOCUMENT BLOCKS FOR CONSUMPTION

type Block struct {
	// Lexer/parser metadata
	Type     string `json:"type"` // "prose" | "code"
	Content  string `json:"content"`
	StartPos Pos    `json:"startPos"`
	EndPos   Pos    `json:"endPos"`

	// OPTIONAL: If evaluated
	Result Atom

	// SyntaxErrors (parser) or RuntimeErrors (evaluator)
	Errors []Error `json:"errors,omitempty"`

	// OPTIONAL: If code block - the parsed expression AST
	rawAST any
}

// for helpers around display
type ExecutionResponse []Block

func (r ExecutionResponse) String() string {
	var sb strings.Builder
	for i := range r {
		block := r[i]

		for _, err := range block.Errors {
			sb.WriteString(err.Error())
			sb.WriteString("\n")
		}

		if len(block.Errors) == 0 && block.Result != nil {
			sb.WriteString(block.Result.String())
			sb.WriteString("\n")
		}
	}
	return sb.String()
}

// CONTEXT

type Context struct {
	userEnv   *env
	importEnv *env

	pkgRegistry map[string]Package
	loadedPkgs  map[string]*env

	replBuf  strings.Builder
	replLine int
}

func NewContext() *Context {
	importEnv := newEnv(nil)
	userEnv := newEnv(importEnv)

	ctx := &Context{
		importEnv:   importEnv,
		userEnv:     userEnv,
		pkgRegistry: make(map[string]Package),
		loadedPkgs:  make(map[string]*env),
		replBuf:     strings.Builder{},
		replLine:    1,
	}

	ctx.RegisterPackage(corePkg)

	err := ctx.ImportPackage("core", "")
	if err != nil {
		panic("Error importing package core: " + err.Error())
	}
	return ctx
}

func (ctx *Context) Reset() {
	ctx.importEnv = newEnv(nil)
	ctx.userEnv = newEnv(ctx.importEnv)
	ctx.replBuf.Reset()
	ctx.replLine = 1
}

func (ctx *Context) ReplPrompt(missingDelims string) string {
	prompt := "jnlisp:" + strconv.Itoa(ctx.replLine) + ":" + missingDelims + "> "
	ctx.replLine++
	return prompt
}

// EXECUTION
// can be in a step() for a REPL or execute() for all in one go

func (ctx *Context) Step(input string) (ExecutionResponse, string) {
	ctx.replBuf.WriteString(input)
	tokens := tokenize(ctx.replBuf.String())

	missingDelims := ""
	incomplete := true

	// -2 to ignore EOF as well
	for i := len(tokens) - 2; i >= 0; i-- {
		if yes, delim := tokens[i].typ.isMissingDelim(); yes {
			missingDelims = delim + missingDelims // prepend with missing delimeter
		} else {
			break // stop looking when no longer doable
		}
	}

	if missingDelims == "" {
		incomplete = false
	}

	for i := 0; i < len(tokens)-len(missingDelims)-1; i++ {
		if tokens[i].typ.isError() {
			incomplete = false
		}
	}

	// if ending on a double newline is definitely complete
	if strings.HasSuffix(strings.TrimRight(ctx.replBuf.String(), " \t"), "\n\n") {
		incomplete = false
	}

	if incomplete {
		return nil, missingDelims
	}

	blocks := parse(ctx.replBuf.String(), tokens)
	ctx.replBuf.Reset()

	blocks = ctx.executeWithEnv(blocks, ctx.userEnv)
	ctx.bindIt(blocks)

	return blocks, ""
}

func (ctx *Context) Execute(input string) ExecutionResponse {
	tokens := tokenize(input)
	blocks := parse(input, tokens)
	blocks = ctx.executeWithEnv(blocks, ctx.userEnv)
	ctx.bindIt(blocks)
	return blocks
}

func (ctx *Context) bindIt(blocks []Block) {
	if len(blocks) == 0 {
		return
	}

	last := blocks[len(blocks)-1]
	if len(last.Errors) > 0 || last.Result == nil {
		return
	}

	ctx.userEnv.bind("it", last.Result)
}

// allows for specific environment for usage with package importing
func (ctx *Context) executeWithEnv(blocks []Block, env *env) []Block {
	var codeBlocks []Block
	for i := range blocks {
		b := blocks[i]
		if b.Type != "code" || len(b.Errors) > 0 {
			continue
		}

		codeBlocks = append(codeBlocks, b)
		block := &codeBlocks[len(codeBlocks)-1]

		expandedAST, err := expand(block.rawAST)
		if err != nil {
			block.Errors = append(block.Errors, err)
			continue
		}

		elaboratedAST, err := elaborate(expandedAST)
		if err != nil {
			block.Errors = append(block.Errors, err)
			continue
		}

		result, err := ctx.eval(elaboratedAST, env, 0)
		if result != nil {
			block.Result = result
		}
		if err != nil {
			block.Errors = append(block.Errors, err)
		}
	}

	return codeBlocks
}

func (ctx *Context) getFSSourceCode(fsys fs.FS) ([]string, Error) {
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
