package jnlisp

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func REPL() {
	context := NewContext()
	reader := bufio.NewReader(os.Stdin)
	println("JNLisp REPL")
	println("Ctrl-c to quit")

	var text strings.Builder
	prompt := buildPrompt(nil)

	for {
		print(prompt)
		newText, _ := reader.ReadString('\n')
		text.WriteString(newText)

		tokens := tokenizeREPL(text.String())
		missing := countMissingTokens(tokens)

		if len(missing) > 0 {
			prompt = buildPrompt(missing)
			continue
		}

		blocks, errors := parseREPL(tokens)

		for i := range errors {
			println(errors[i].Error())
		}

		if len(errors) > 0 {
			text.Reset()
			prompt = buildPrompt(nil)
			continue
		}

		// loop through expressions in ast and evaluate them
		for i := range blocks {
			ast, err := expand(blocks[i])
			if err != nil {
				text.Reset()
				println(err.Error())
				continue
			}

			expr, err := elaborate(ast)
			if err != nil {
				text.Reset()
				println(err.Error())
				continue
			}
			fmt.Printf("%v\n", expr)

			// TODO include elaboration here

			atom, err := eval(ast, context)
			if err != nil {
				text.Reset()
				println(err.Error())
				continue
			}

			println(atom.String())
		}

		text.Reset()
		prompt = buildPrompt(nil)
	}
}

func buildPrompt(missingDelims []string) (prompt string) {
	for _, delim := range missingDelims {
		prompt += delim
	}
	prompt += "> "
	return
}
