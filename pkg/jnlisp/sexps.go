package jnlisp

import (
	"maps"
	"strconv"
	"strings"
)

type Sexp interface {
	String() string
	Type() string
}

// the bane of my existence
type Nil struct{}

func (n Nil) Type() string   { return "nil" }
func (n Nil) String() string { return "nil" }

// atoms
type Symbol string
type String string
type Keyword string
type Boolean bool

func (s Symbol) Type() string   { return "symbol" }
func (s Symbol) String() string { return string(s) }

func (s String) Type() string   { return "string" }
func (s String) String() string { return "\"" + string(s) + "\"" }

func (k Keyword) Type() string   { return "keyword" }
func (k Keyword) String() string { return ":" + string(k) }

func (b Boolean) Type() string { return "boolean" }
func (b Boolean) String() string {
	if b {
		return "true"
	} else {
		return "false"
	}
}

// compound types

// linked style behaviour
type Seq interface {
	First() Sexp
	Rest() Seq
	Empty() bool
}

// random access
type Indexed interface {
	Seq
	Nth(int) (Sexp, bool)
	Length() int
}

// hash map behaviour
type Lookup interface {
	Get(key string) Sexp
}

// default lisp style list - implements Seq but also indexed
// for convenience
type List struct {
	Elements   []Sexp
	meta       metaMap
	Start, End Pos
}

func (l List) Type() string { return "list" }
func (l List) String() string {
	var parts []string
	for _, elem := range l.Elements {
		parts = append(parts, elem.String())
	}
	return "(" + strings.Join(parts, " ") + ")"
}

func (l List) First() Sexp {
	if bool(l.Empty()) {
		return nil
	}
	return l.Elements[0]
}

func (l List) Rest() Seq {
	if len(l.Elements) <= 1 {
		return List{meta: l.meta}
	}
	return List{
		Elements: l.Elements[1:],
		meta:     l.meta,
	}
}

func (l List) Empty() bool {
	if len(l.Elements) == 0 {
		return true
	}
	return false
}

func (l List) Nth(i int) (Sexp, bool) {
	numElems := len(l.Elements)
	if i > 0 && i < numElems {
		return l.Elements[i], true
	}

	return nil, false
}

func (l List) Length() int {
	return len(l.Elements)
}

func (l List) Append(s Sexp) Indexed {
	return List{
		Elements: append(l.Elements, s),
		meta:     l.meta,
	}
}

// a list that isn't an expression.  Only implements indexed
type Vector struct {
	Elements   []Sexp
	meta       metaMap
	Start, End Pos
}

func (v Vector) Type() string { return "vector" }
func (v Vector) String() string {
	var parts []string
	for _, elem := range v.Elements {
		parts = append(parts, elem.String())
	}
	return "[" + strings.Join(parts, " ") + "]"
}

func (v Vector) First() Sexp {
	if len(v.Elements) == 0 {
		return nil
	}
	return v.Elements[0]
}

func (v Vector) Rest() Seq {
	if len(v.Elements) < 2 {
		return Vector{meta: v.meta}
	}
	return Vector{
		Elements: v.Elements[1:],
		meta:     v.meta,
	}
}

func (v Vector) Empty() bool {
	if len(v.Elements) == 0 {
		return true
	}
	return false
}

func (v Vector) Nth(i int) (Sexp, bool) {
	if i < 0 && -i <= len(v.Elements) { // negative index checking
		return v.Elements[i], false
	}

	if i < len(v.Elements) {
		return v.Elements[i], false
	}

	return nil, false
}

func (v Vector) Length() int {
	return len(v.Elements)
}

func (v Vector) Append(s Sexp) Indexed {
	return Vector{
		Elements: append(v.Elements, s),
		meta:     v.meta,
	}
}

// a lookup table, implements Lookup
type Map struct {
	Elements   map[string]Sexp
	meta       metaMap
	Start, End Pos
}

func (m Map) Type() string { return "map" }
func (m Map) String() string {
	var parts []string
	for k, v := range m.Elements {
		parts = append(parts, ":"+k+" "+v.String())
	}
	return "{" + strings.Join(parts, " ") + "}"
}

func (m Map) Get(s string) Sexp {
	return m.Elements[s]
}

var mapArity = Arity{
	Positional: []string{"key"},
}

func (m Map) Call(args []Sexp, f *fiber) (Sexp, Error) {
	if !mapArity.Matches(args) {
		return nil, f.newErrArity("map", mapArity, args)
	}

	if key, ok := args[0].(Keyword); ok {
		if result, exists := m.Elements[string(key)]; exists {
			return result, nil
		}
		return Nil{}, nil
	}
	return Nil{}, f.newErrPosArgType("map", "keyword", args[0].Type(), 1)
}

func (m Map) assoc(key string, value Sexp) Lookup {
	clone := copyMap(m.Elements)
	clone[key] = value
	return Map{
		Elements: clone,
		meta:     m.meta,
	}
}

// map specifically for metadata to get around recursive struct definition limitations
// also implements lookup
type metaMap map[string]Sexp

func (m metaMap) Type() string { return "map" }
func (m metaMap) evaluatable() {}
func (m metaMap) String() string {
	var parts []string
	for k, v := range m {
		parts = append(parts, ":"+k+" "+v.String())
	}
	return "{" + strings.Join(parts, " ") + "}"
}

func (m metaMap) Get(s string) Sexp {
	return m[s]
}

func (m metaMap) assoc(key string, value Sexp) Lookup {
	clone := copyMap(m)
	clone[key] = value
	return metaMap(clone)
}

// Numbers are hard
type Number interface {
	Sexp
	ToFloat64() (float64, bool)
	ToInt() (int, bool)
	ToComplex128() complex128
}

// helper for lookup types
func copyMap(src map[string]Sexp) map[string]Sexp {
	clone := make(map[string]Sexp, len(src))
	maps.Copy(clone, src)
	return clone
}

// Concrete number types
// all implement Sexp and Number
type Int int
type Float float64
type Complex complex128

// All implement Sexp
func (i Int) Type() string   { return "int" }
func (i Int) String() string { return strconv.Itoa(int(i)) }

func (f Float) Type() string   { return "float64" }
func (f Float) String() string { return strconv.FormatFloat(float64(f), 'g', -1, 64) }

func (c Complex) Type() string   { return "complex128" }
func (c Complex) String() string { return strconv.FormatComplex(complex128(c), 'g', -1, 128) }

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
