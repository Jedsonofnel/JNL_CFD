//go:build !wasm && !js

package main

import (
	_ "embed"
	"errors"
	"fmt"
	"os"

	"github.com/Jedsonofnel/jnlcfd/cfd/nativedisp"
	"github.com/Jedsonofnel/jnlcfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/linalg"

	jnl "jedn.dev/jnlisp"
	"jedn.dev/jnlisp/stdlib"
)

var runtime *jnl.Runtime

//go:embed cli.jnl
var cliSrc string

var cliNS = jnl.NewNamespace("jnlCFD", cliSrc)

func init() {
	runtime = jnl.NewRuntime(
		os.Stdin,
		os.Stdout,
		os.Stderr,
		os.DirFS("."),
	)

	runtime.RegisterNamespace(linalg.NS)
	runtime.RegisterNamespace(geometry.NS)
	runtime.RegisterNamespace(fvm.NS)
	runtime.RegisterNamespace(nativedisp.NS)

	stdlib.RegisterEntirety(runtime)

	runtime.RegisterNamespace(cliNS)
}

func main() {
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
	session := runtime.NewREPLSession(cliNS)
	err := session.RunMain(cliNS)
	if err != nil {
		return jnl.FormatError(err, runtime)
	}

	if err := session.REPL(""); err != nil {
		return session.SimpleREPL("")
	}

	return nil
}
