package jnlisp

import (
	"embed"
	"math"
)

//go:embed mathslib.jnl
var mathsLibFS embed.FS

var mathsPkg = Package{
	Name: "maths",
	FS:   mathsLibFS,
	Bindings: map[string]NativeFunction{
		"sin":  lispSine,
		"cos":  lispCosine,
		"sqrt": lispSqrt,
	},
	Atoms: map[string]Atom{},
}

func lispSine(args []Atom, kwargs TableAtom) (Atom, Error) {
	num, v := ValidateArgs(args, kwargs).GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate("sin"); err != nil {
		return nil, err
	}

	return NumberAtom{math.Sin(num)}, nil
}

func lispCosine(args []Atom, kwargs TableAtom) (Atom, Error) {
	num, v := ValidateArgs(args, kwargs).GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate("cos"); err != nil {
		return nil, err
	}

	return NumberAtom{math.Cos(num)}, nil
}

func lispSqrt(args []Atom, kwargs TableAtom) (Atom, Error) {
	num, v := ValidateArgs(args, kwargs).GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate("cos"); err != nil {
		return nil, err
	}

	if num < 0 {
		return nil, RuntimeError{Message: "sqrt expects a positive number"}
	}

	return NumberAtom{math.Sqrt(num)}, nil
}
