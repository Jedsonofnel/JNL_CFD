package jnlisp

import (
	"embed"
	"fmt"
	"math"
)

//go:embed mathslib.jnl
var mathsLibSrc embed.FS

func init() {
	RegisterLibrary(Library{
		Name: "maths",
		Src:  mathsLibSrc,
		Bindings: map[string]ProcFunc{
			"sin":  lispSine,
			"cos":  lispCosine,
			"sqrt": lispSqrt,
		},
		Atoms: map[string]Atom{},
	})
}

func lispSine(args []Atom, _ table) (Atom, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("sin expects exactly 1 argument, got %d", len(args))
	}

	num, ok := args[0].(NumberAtom)
	if !ok {
		return nil, fmt.Errorf("cos expects a number, got %s", args[0].Type())
	}

	castArgs, err := toRational([]any{num.value}, "sin")
	if err != nil {
		return nil, err
	}

	return NumberAtom{math.Sin(castArgs[0])}, nil
}

func lispCosine(args []Atom, _ table) (Atom, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("cos expects exactly 1 argument, got %d", len(args))
	}

	num, ok := args[0].(NumberAtom)
	if !ok {
		return nil, fmt.Errorf("cos expects a number, got %s", args[0].Type())
	}

	castArgs, err := toRational([]any{num.value}, "cos")
	if err != nil {
		return nil, err
	}

	return NumberAtom{math.Cos(castArgs[0])}, nil
}

func lispSqrt(args []Atom, _ table) (Atom, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("sqrt expects exactly 1 argument, got %d", len(args))
	}

	num, ok := args[0].(NumberAtom)
	if !ok {
		return nil, fmt.Errorf("sqrt expects numbers, got %s", args[0].Type())
	}

	castArgs, err := toRational([]any{num.value}, "sqrt")
	if err != nil {
		return nil, err
	}
	arg := castArgs[0]

	if arg < 0 {
		return nil, fmt.Errorf("sqrt expects a postiive number, got %v", arg)
	}

	return NumberAtom{math.Sqrt(arg)}, nil
}
