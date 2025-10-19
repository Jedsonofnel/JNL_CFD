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
		"sin":  SimpleNative(lispSine),
		"cos":  SimpleNative(lispCosine),
		"sqrt": SimpleNative(lispSqrt),
	},
	Sexps: map[string]Sexp{},
}

func lispSine(args []Sexp, kwargs Table) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	num := v.GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate("sin"); err != nil {
		return nil, err
	}

	return Float(math.Sin(num)), nil
}

func lispCosine(args []Sexp, kwargs Table) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	num := v.GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate("cos"); err != nil {
		return nil, err
	}

	return Float(math.Cos(num)), nil
}

func lispSqrt(args []Sexp, kwargs Table) (Sexp, Error) {
	v := ValidateArgs(args, kwargs)
	num := v.GetFloat64()
	v.ExpectNoMoreArgs()
	if err := v.Validate("cos"); err != nil {
		return nil, err
	}

	if num < 0 {
		return nil, RuntimeError{Message: "sqrt expects a positive number"}
	}

	return Float(math.Sqrt(num)), nil
}
