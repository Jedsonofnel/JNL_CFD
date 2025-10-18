package main

import (
	"bufio"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

func main() {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT)

	go func() {
		<-sigChan
		fmt.Println("\nGoodbye!")
		os.Exit(0)
	}()

	ctx := jnlisp.NewContext()
	reader := bufio.NewReader(os.Stdin)

	fmt.Println("JNLisp REPL")
	fmt.Println("Ctrl-c to quit")

	for {
		fmt.Print("> ")

		line, err := reader.ReadString('\n')
		if err != nil {
			fmt.Println("Error getting input")
			break
		}

		blocks, promptDisplay := ctx.Step(line)

		fmt.Print(blocks.String())
		fmt.Print(promptDisplay)
	}
}
