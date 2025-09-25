package jnlisp

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

var globalEnv = newStandardEnv()

// public entrypoint
func REPL() {
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
			exp, err := eval(exp, globalEnv)
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

func tokenizeREPL(input string) []token {
	l := lex(input, lexScanExpr)
	tokens := make([]token, 0)

	for {
		next := l.nextItem()
		if next.typ == tokenEOF || next.typ == tokenError {
			tokens = append(tokens, next)
			break
		}
		tokens = append(tokens, next)
	}

	return tokens
}

func tokenizeMd(input string) string {
	lex := lex(input, lexScanMdExpr)
	tokens := make([]token, 0)

	for {
		next := lex.nextItem()
		if next.typ == tokenEOF || next.typ == tokenError {
			break
		}
		tokens = append(tokens, next)
	}

	return fmt.Sprintf("%v", tokens)
}

func buildPrompt(missingParens int) (prompt string) {
	for range missingParens {
		prompt += "("
	}
	prompt += "> "
	return
}

func validateTokens(tokens []token) (int, error) {
	count := 0
	for _, token := range tokens {
		if token.typ == tokenMissingParen {
			count++
		}

		if token.typ == tokenError {
			return 0, fmt.Errorf("%s", token.val)
		}
	}

	return count, nil
}
