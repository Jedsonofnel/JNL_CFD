package jnlisp

import (
	"strconv"
	"strings"
)

type REPL struct {
	vm  *VM
	env *env

	document Document

	line  int
	start Pos
	buf   strings.Builder

	missingDelims string
}

func NewREPL(vm *VM) *REPL {
	return &REPL{
		vm:  vm,
		env: newEnv(vm.userEnv),

		document: []Block{},

		line:  0,
		start: Pos{1, 1, 0},
		buf:   strings.Builder{},

		missingDelims: "",
	}
}

func (r *REPL) Feed(input string) string {
	r.buf.WriteString(input)

	newBlocks := parse(Source{
		Filename: "repl",
		Text:     r.buf.String(),
		Start:    r.start,
	})

	if len(newBlocks) == 0 {
		r.buf.Reset()
		return ""
	}

	block := newBlocks[len(newBlocks)-1] // should only ever have length
	for _, err := range block.Errors {
		if missing, ok := err.(missingDelim); ok {
			r.missingDelims += missing.matching()
		} else {
			r.buf.Reset()
			r.start = Pos{r.line + 1, 1, 0}
			return block.SyntaxErrors()
		}
	}

	if r.missingDelims != "" {
		return ""
	}

	r.buf.Reset()
	r.missingDelims = ""
	r.start = Pos{r.line + 1, 1, 0}

	if block.BlockType != CodeBlock {
		return "<prose>"
	}

	fiber := &fiber{
		maxDepth: 1000,
		block:    &block,
	}

	result, err := fiber.eval(block.AST, r.env)
	if err != nil {
		return err.PrettyError()
	}

	r.document = append(r.document, block)
	return result.String()
}

func (r *REPL) Prompt() string {
	r.line++
	prompt := "jnlisp:" + strconv.Itoa(r.line) + ":" + r.missingDelims + "> "
	return prompt
}
