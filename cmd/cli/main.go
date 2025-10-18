package main

import (
	"flag"
	"fmt"

	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

var ctx *jnlisp.Context

func init() {
	ctx = jnlisp.NewContext()
}

func main() {
	flag.Parse()
	// filename := flag.Arg(0)

	fmt.Printf("Hello")
}
