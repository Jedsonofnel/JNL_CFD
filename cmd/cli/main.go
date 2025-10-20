package main

import (
	"flag"
	"fmt"

	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)
func main() {
	vm := jnlisp.NewVM()
	vm.Reset()
	flag.Parse()
	// filename := flag.Arg(0)

	fmt.Printf("hello")
}
