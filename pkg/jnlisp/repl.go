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
	fmt.Println("JNLisp REPL")
	fmt.Println("Ctrl-c to quit")

	var text strings.Builder
	prompt := buildPrompt(0)

	for {
		fmt.Print(prompt)
		newText, _ := reader.ReadString('\n')
		text.WriteString(newText)
		tokens := tokenizeREPL(text.String())

		missing, err := validateTokens(tokens)
		if err != nil {
			text.Reset()
			fmt.Printf("error: %s\n", err)
			prompt = buildPrompt(0)
			continue
		}

		if missing > 0 {
			prompt = buildPrompt(missing)
			continue
		}

		ast, err := parseREPL(tokens)
		if err != nil {
			text.Reset()
			fmt.Printf("error: %s\n", err)
			continue
		}

		// loop through expressions in ast and evaluate them
		for _, exp := range ast {
			exp, err := eval(exp, context)
			if err != nil {
				text.Reset()
				fmt.Printf("error: %s\n", err)
				continue
			}

			fmt.Printf("%v\n", exp)
		}
		text.Reset()
		prompt = buildPrompt(0)
	}
}

func buildPrompt(missingParens int) (prompt string) {
	for range missingParens {
		prompt += "("
	}
	prompt += "> "
	return
}
