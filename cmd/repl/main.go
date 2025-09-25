package main

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT)

	go func() {
		<-sigChan
		fmt.Println("\nGoodbye!")
		os.Exit(0)
	}()

	jnlisp.REPL()
}
