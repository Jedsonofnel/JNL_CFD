package jnlisp

import (
	"bufio"
	"os"
	"strings"
)

type REPLResponse struct {
	Output string
	Done   bool
}

func REPL() {
	context := NewContext()
	reader := bufio.NewReader(os.Stdin)
	var accumulator strings.Builder

	println("JNLisp REPL")
	println("Ctrl-c to quit")

	for {
		if accumulator.Len() == 0 {
			print("> ")
		}

		line, err := reader.ReadString('\n')
		if err != nil {
			println("Error reading input")
			break
		}

		accumulator.WriteString(line)
		rr := Read(accumulator.String())

		if rr.abandoned {
			println("Abandoned input - resetting")
			accumulator.Reset()
			continue
		}

		if len(rr.missingDelims) != 0 {
			print(buildPrompt(rr.missingDelims))
			continue
		}

		// loop through blocks
		for i := range rr.blocks {
			block := rr.blocks[i]

			if block.Type == "prose" || len(block.Errors) > 0 {
				accumulator.Reset()
				continue
			}

			for _, err := range block.Errors {
				println(err.Error())
			}

			ast, err := expand(block.rawAST)
			if err != nil {
				accumulator.Reset()
				println(err.Error())
				continue
			}

			expr, err := elaborate(ast)
			if err != nil {
				accumulator.Reset()
				println(err.Error())
				continue
			}

			atom, err := eval(expr, context)
			if err != nil {
				accumulator.Reset()
				println(err.Error())
				continue
			}

			println(atom.String())
		}

		accumulator.Reset()
	}
}

type readResponse struct {
	blocks        []Block  // results of parser
	abandoned     bool     // if terminated by REPL double newline
	missingDelims []string // any recoverable missing delims
}

// returns
func Read(input string) readResponse {
	tokens := tokenize(input)
	modeToken := tokens[0].typ
	tokens = tokens[1:]

	// early return if abandoned
	if tokens[0].typ == tokenAbandoned {
		return readResponse{abandoned: true}
	}

	// early return if document
	if modeToken == tokenDocument {
		blocks := parse(input, tokens)
		return readResponse{blocks: blocks}
	}

	// if not document then REPL
	// check if missing parens AND recoverable
	var recoverable = true
	var missingDelims []string

	for i := range tokens {
		if yes, delim := tokens[i].typ.isMissingDelim(); yes {
			missingDelims = append(missingDelims, delim)
		} else if tokens[i].typ.isError() {
			recoverable = false
		}
	}

	// early return if it's recoverable and there are missing delims
	if recoverable && len(missingDelims) != 0 {
		return readResponse{missingDelims: missingDelims}
	}

	blocks := parse(input, tokens)
	return readResponse{blocks: blocks}
}

func buildPrompt(missingDelims []string) (prompt string) {
	for _, delim := range missingDelims {
		prompt += delim
	}
	prompt += "> "
	return
}
