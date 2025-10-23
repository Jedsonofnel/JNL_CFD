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
	vm := jnlisp.NewVM()
	repl := jnlisp.NewREPL(vm)

	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		simpleREPL(repl)
		return
	}
	defer term.Restore(int(os.Stdin.Fd()), oldState)

	writeline("JNLisp REPL")
	writeline("Ctrl-d to quit, Ctrl-l to clear, Ctrl-c to cancel line")

REPL:
	for {
		line, interrupt := readline(repl.Prompt())

		switch interrupt {
		case InterruptCancel:
			continue REPL
		case InterruptEOF:
			break REPL
		}

		line += "\n"
		result := repl.Feed(line)
		if result != "" {
			writeline(result)
		}
	}
}

// Fallback for when raw mode isn't available
func simpleREPL(repl *jnlisp.REPL) {
	reader := bufio.NewReader(os.Stdin)

	fmt.Println("JNLisp REPL (simple mode)")
	fmt.Println("Ctrl-C to quit")

	for {
		fmt.Print(repl.Prompt())
		line, _ := reader.ReadString('\n')
		result := repl.Feed(line)
		fmt.Println(result)
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
				if line.Len() == 0 {
					return "", InterruptEOF
				}
				return "", InterruptCancel
			case '\x04': // <c-d> is EOF
				fmt.Print("\r\n")
				return "", InterruptEOF
			case '\x0c': // <c-l> is clear
				fmt.Print("\x1b[H\x1b[2J")
				fmt.Print(prompt + line.String())
			case 127, 8: // backspace
				s := line.String()
				if len(s) == 0 {
					continue
				}
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

func writeline(s string) {
	// normalise newlines
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\n", "\r\n")

	if !strings.HasSuffix(s, "\r\n") {
		s += "\r\n"
	}

	fmt.Print(s)
}
