//go:build !wasm

package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/nativedisp"

	jnl "jedn.dev/jnlisp"
	"jedn.dev/jnlisp/cli"
)

var header string = `
       _       __________________ 
      (_)___  / / ____/ ____/ __ \
     / / __ \/ / /   / /_  / / / /
    / / / / / / /___/ __/ / /_/ / 
 __/ /_/ /_/_/\____/_/   /_____/  
/___/                             `

var runtime *jnl.Runtime

func init() {
	lispIO := jnl.IO{
		FS:     os.DirFS("."),
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}

	runtime = jnl.NewRuntime(lispIO)
	runtime.RegisterNamespace(linalg.NS)
	runtime.RegisterNamespace(geometry.NS)
	runtime.RegisterNamespace(fvm.NS)
	runtime.RegisterNamespace(nativedisp.NS)
}

func main() {
	fmt.Println(header)
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	switch len(os.Args[1:]) {
	case 0:
		return startREPL()
	}
	return errors.New("jnlcfd does not expect any args")
}

func startREPL() error {
	repl := cli.NewREPL(runtime, "jnlCFD REPL")
	repl.SetNamespace("jnlcfd")

	var err error
	err = repl.LoadAndRefer(geometry.NS, "")
	err = repl.LoadAndRefer(nativedisp.NS, "")
	err = repl.LoadAndRefer(fvm.NS, "")
	err = repl.LoadAndRefer(linalg.NS, "")

	if err != nil {
		return jnl.FormatError(err)
	}

	if err := repl.RawTerminal(); err != nil {
		return repl.SimpleTerminal()
	}
	return nil
}
