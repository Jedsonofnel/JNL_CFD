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

// can call a keyword with a map
var keywordArity = Arity{Positional: []string{"lookup"}}

func (k Keyword) Call(args []Sexp, f *fiber) (Sexp, Error) {
	av := ValidateArgs(args, keywordArity, f, "keyword")
	mapp := GetArg[Lookup](av)
	return mapp.Get(string(k)), nil
}

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
	Sexp
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
	Sexp
	Get(key string) Sexp
}

// the bane of my existence.  Distinct from the empty list
type Nil struct{}

func (n Nil) Type() string   { return "nil" }
func (n Nil) String() string { return "nil" }

func (n Nil) First() Sexp { return Nil{} }
func (n Nil) Rest() Seq   { return Nil{} }
func (n Nil) Empty() bool { return true }

// default lisp style list - implements Seq but also indexed
// for convenience
type List struct {
	Elements   []Sexp
	start, end Pos
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
	if l.Empty() {
		return Nil{}
	}
	return l.Elements[0]
}

func (l List) Rest() Seq {
	numElems := len(l.Elements)
	if numElems == 0 {
		return Nil{}
	}

	return List{
		Elements: l.Elements[1:],
	}
}

func (l List) Empty() bool {
	return len(l.Elements) == 0
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
	}
}

// a list that isn't an expression.  Only implements indexed
type Vector struct {
	Elements   []Sexp
	start, end Pos
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
		return Nil{}
	}
	return v.Elements[0]
}

func (v Vector) Rest() Seq {
	numElems := len(v.Elements)
	if numElems == 0 {
		return Nil{}
	}

	return Vector{
		Elements: v.Elements[1:],
	}
}

func (v Vector) Empty() bool {
	if len(v.Elements) == 0 {
		return true
	}
	return false
}

func (v Vector) Nth(i int) (Sexp, bool) {
	if i < len(v.Elements) {
		return v.Elements[i], true
	}

	return nil, false
}

func (v Vector) Length() int {
	return len(v.Elements)
}

func (v Vector) Append(s Sexp) Indexed {
	return Vector{
		Elements: append(v.Elements, s),
	}
}

var vectorArity = Arity{
	Positional: []string{"index"},
}

func (v Vector) Call(args []Sexp, f *fiber) (Sexp, Error) {
	av := ValidateArgs(args, vectorArity, f, "vector")
	idx := GetArg[Int](av)

	if value, ok := v.Nth(int(idx)); ok {
		return value, nil
	}

	return Nil{}, f.newErrIndexOutOfRange(int(idx), v.Length())
}

// a lookup table, implements Lookup
type Map struct {
	Elements   map[string]Sexp
	order      []string
	start, end Pos
}

func (m Map) Type() string { return "map" }
func (m Map) String() string {
	var parts []string
	for k, v := range m.Elements {
		parts = append(parts, ":"+k+" "+v.String())
	}
	return "{" + strings.Join(parts, " ") + "}"
}

// Lookup implementation
func (m Map) Get(s string) Sexp {
	return m.Elements[s]
}

// Seq implementation
func (m Map) First() Sexp {
	if len(m.order) == 0 {
		return Nil{}
	}
	key := m.order[0]
	return Vector{
		Elements: []Sexp{Keyword(key), m.Elements[key]},
	}
}

func (m Map) Rest() Seq {
	if len(m.Elements) == 0 {
		return Nil{}
	}

	newOrder := make([]string, len(m.order)-1)
	copy(newOrder, m.order[1:])

	newElems := make(map[string]Sexp, len(newOrder))
	for _, key := range newOrder {
		newElems[key] = m.Elements[key]
	}

	return Map{
		Elements: newElems,
		order:    newOrder,
	}
}

func (m Map) Empty() bool {
	return len(m.Elements) == 0
}

var mapArity = Arity{
	Positional: []string{"key"},
}

func (m Map) Call(args []Sexp, f *fiber) (Sexp, Error) {
	av := ValidateArgs(args, mapArity, f, "map")
	key := GetArg[Keyword](av)
	if err := av.Validate(); err != nil {
		return Nil{}, err
	}

	if result, exists := m.Elements[string(key)]; exists {
		return result, nil
	}

	return Nil{}, nil
}

func (m Map) assoc(key string, value Sexp) Lookup {
	cloneElems := make(map[string]Sexp, len(m.Elements))
	maps.Copy(cloneElems, m.Elements)
	cloneElems[key] = value

	cloneOrder := make([]string, 0, len(m.order)+1)
	copy(cloneOrder, m.order)

	return Map{
		Elements: cloneElems,
		order:    cloneOrder,
	}
}

// mutable append type for internal bits
func (m *Map) append(key string, value Sexp) {
	m.order = append(m.order, key)
	m.Elements[key] = value
}

// Numbers are hard
type Number interface {
	Sexp
	ToFloat64() (float64, bool)
	ToInt() (int, bool)
	ToComplex128() complex128
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

func (c Complex) Type() string { return "complex128" }
func (c Complex) String() string {
	format := strconv.FormatComplex(complex128(c), 'g', -1, 128)
	return strings.Trim(format, "()")
}

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

func PromoteNumbersTo(numbers ...Number) string {
	hasFloat := false
	for _, n := range numbers {
		switch n.(type) {
		case Complex:
			return "complex128"
		case Float:
			hasFloat = true
		}
	}

	if hasFloat {
		return "float64"
	}
	return "int"
}

// helper for uniformly formatting non-readable Sexp types
func FormatNonReadable(category, name string, details ...string) string {
	acc := strings.Builder{}
	acc.WriteString("#<")

	switch {
	case name == "" && len(details) == 0:
		acc.WriteString(category)
	case name == "":
		acc.WriteString(category)
		acc.WriteString(":")
		acc.WriteString(strings.Join(details, " "))
	case len(details) == 0:
		acc.WriteString(category)
		acc.WriteString(":")
		acc.WriteString(name)
	default:
		acc.WriteString(category)
		acc.WriteString(":")
		acc.WriteString(name)
		acc.WriteString(" ")
		acc.WriteString(strings.Join(details, " "))
	}

	acc.WriteString(">")
	return acc.String()
}
