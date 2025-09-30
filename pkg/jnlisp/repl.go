package jnlisp

import (
	"bufio"
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

		exps, errors := parseREPL(tokens)
		for i := range errors {
			println(errors[i].Error())
		}

		if len(errors) > 0 {
			text.Reset()
			prompt = buildPrompt(nil)
			continue
		}

		// loop through expressions in ast and evaluate them
		for i := range exps {
			exp, err := eval(exps[i], context)

			if err != nil {
				text.Reset()
				println("ERROR EVALUATING: ", err.Error())
				continue
			}

			println(exp.String())
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
