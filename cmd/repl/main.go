package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"golang.org/x/term"

	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

func main() {
	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		simpleREPL()
		return
	}
	defer term.Restore(int(os.Stdin.Fd()), oldState)

	ctx := jnlisp.NewContext()

	fmt.Print("JNLisp REPL\r\n")
	fmt.Print("Ctrl-d to quit, Ctrl-l to clear, Ctrl-c to cancel line\r\n")

	for {
		result, shouldExit := readCompleteForm(ctx)
		if shouldExit {
			break // so that defer runs
		}
		fmt.Print(result + "\r")
	}
}

func readCompleteForm(ctx *jnlisp.Context) (string, bool) {
	prompt := ctx.ReplPrompt("")

	for {
		line, interrupt := readline(prompt)

		if interrupt == InterruptCancel {
			continue // cancelled - restart with new prompt
		}

		if interrupt == InterruptEOF {
			return "", true
		}

		line += "\n"
		blocks, missingDelims := ctx.Step(line)

		if blocks != nil { // input is complete
			return blocks.String(), false
		}

		prompt = ctx.ReplPrompt(missingDelims)
	}
}

// Fallback for when raw mode isn't available
func simpleREPL() {
	ctx := jnlisp.NewContext()
	reader := bufio.NewReader(os.Stdin)

	fmt.Println("JNLisp REPL (simple mode)")
	fmt.Println("Ctrl-C to quit")

	for {
		fmt.Print("> ")
		line, _ := reader.ReadString('\n')
		blocks, promptDisplay := ctx.Step(line)
		fmt.Print(blocks.String())
		fmt.Print(promptDisplay)
	}
}

// READLINE IMPLEMENTATION (goodness)

type interrupt int

const (
	NoInterrupt interrupt = iota
	InterruptCancel
	InterruptEOF
)

func readline(prompt string) (string, interrupt) {
	fmt.Print(prompt)

	var line strings.Builder
	buf := make([]byte, 4)

	for {
		// read first byte
		n, err := os.Stdin.Read(buf[:1])
		if err != nil || n == 0 {
			return "", InterruptEOF
		}

		c := buf[0]

		// ASCII - check for control characters
		if c < 128 {
			switch c {
			case '\x03': // <c-c> is cancel
				fmt.Print("\r\n")
				return "", InterruptCancel
			case '\x04': // <c-d> is EOF
				return "", InterruptEOF
			case '\x0c': // <c-l> is clear
				fmt.Print("\x1b[H\x1b[2J")
				fmt.Print(prompt + line.String())
			case 127, 8: // backspace
				s := line.String()
				line.Reset()
				line.WriteString(s[:len(s)-1])
				fmt.Print("\b \b") // visual erase for single column char
			case '\r', '\n':
				fmt.Print("\r\n")
				return line.String(), 0
			default:
				if c >= 32 {
					line.WriteByte(c)
					fmt.Printf("%c", c)
				}
			}
			continue
		}

		// Multi-byte UTF-8
		var size int
		switch {
		case c >= 0xF0:
			size = 4
		case c >= 0xE0:
			size = 3
		case c >= 0xC0:
			size = 2
		default:
			continue // invalid UTF-8
		}

		_, err = os.Stdin.Read(buf[1:size])
		if err != nil {
			continue
		}

		for i := range size {
			line.WriteByte(buf[i])
		}

		fmt.Print(string(buf[:size]))
	}
}
