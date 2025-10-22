package jnlisp

import (
	"strconv"
	"strings"
)

type Sexp interface {
	evaluatable
	String() string
	Type() string
}

type evaluatable interface {
	evaluatable()
}

type Symbol string
type String string
type Keyword string
type Boolean bool
type List []Sexp
type Vector []Sexp
type Map map[string]Sexp

func (s Symbol) Type() string   { return "symbol" }
func (s Symbol) String() string { return string(s) }
func (s Symbol) evaluatable()   {}

func (s String) Type() string   { return "string" }
func (s String) String() string { return "\"" + string(s) + "\"" }
func (s String) evaluatable()   {}

func (k Keyword) Type() string   { return "keyword" }
func (k Keyword) String() string { return ":" + string(k) }
func (k Keyword) evaluatable()   {}

func (b Boolean) Type() string { return "boolean" }
func (b Boolean) evaluatable() {}
func (b Boolean) String() string {
	if b {
		return "true"
	} else {
		return "false"
	}
}

func (l List) Type() string { return "list" }
func (l List) evaluatable() {}
func (l List) String() string {
	var parts []string
	for _, elem := range l {
		parts = append(parts, elem.String())
	}
	return "(" + strings.Join(parts, " ") + ")"
}

func (v Vector) Type() string { return "vector" }
func (v Vector) evaluatable() {}
func (v Vector) String() string {
	var parts []string
	for _, elem := range v {
		parts = append(parts, elem.String())
	}
	return "[" + strings.Join(parts, " ") + "]"
}

func (m Map) Type() string { return "map" }
func (m Map) evaluatable() {}
func (m Map) String() string {
	var parts []string
	for k, v := range m {
		parts = append(parts, ":"+k+" "+v.String())
	}
	return "{" + strings.Join(parts, " ") + "}"
}

// Numbers are hard
type Number interface {
	Sexp
	ToFloat64() (float64, bool)
	ToInt() (int, bool)
	ToComplex128() complex128
}

// Concrete number types
type Int int
type Float float64
type Complex complex128

// All implement Sexp
func (i Int) Type() string   { return "number (int)" }
func (i Int) String() string { return strconv.Itoa(int(i)) }
func (i Int) evaluatable()   {}

func (f Float) Type() string   { return "number (float)" }
func (f Float) String() string { return strconv.FormatFloat(float64(f), 'g', -1, 64) }
func (f Float) evaluatable()   {}

func (c Complex) Type() string   { return "number (complex)" }
func (c Complex) String() string { return strconv.FormatComplex(complex128(c), 'g', -1, 128) }
func (c Complex) evaluatable()   {}

// And implement Number
func (i Int) ToFloat64() (float64, bool) { return float64(i), true }
func (i Int) ToInt() (int, bool)         { return int(i), true }
func (i Int) ToComplex128() complex128   { return complex(float64(i), 0) }

func (f Float) ToFloat64() (float64, bool) { return float64(f), true }
func (f Float) ToInt() (int, bool)         { return int(f), true } // lossy but ok
func (f Float) ToComplex128() complex128   { return complex(float64(f), 0) }

func (c Complex) ToFloat64() (float64, bool) {
	if imag(c) == 0 {
		return real(c), true
	}
	return 0, false // can't convert complex with imaginary part
}
func (c Complex) ToInt() (int, bool) {
	if imag(c) == 0 {
		return int(real(c)), true
	}
	return 0, false
}
func (c Complex) ToComplex128() complex128 { return complex128(c) }
