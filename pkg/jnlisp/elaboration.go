package jnlisp

import (
	"strings"
)

func (f *fiber) elaborate(sexp Sexp) (Sexp, Error) {
	defer f.pop()

	switch s := sexp.(type) {
	case List:
		if s.Length() == 0 {
			return nil, f.newErrElaborationSyntax("cannot evaluate the empty list")
		}
		f.push(s, 0, opElaborate)
		return elaborateCall(s, f)
	case Vector:
		for i, elem := range s.Elements {
			f.push(elem, i, opElaborate)
			elaborated, err := f.elaborate(elem)
			if err != nil {
				return nil, err
			}
			s.Elements[i] = elaborated
		}
		return s, nil
	case Map:
		for key, value := range s.Elements {
			f.pushMapValue(value, key, opElaborate)
			elaborated, err := f.elaborate(value)
			if err != nil {
				return nil, err
			}
			s.Elements[key] = elaborated
		}
		return s, nil
	default: // most types don't need elaboration
		return s, nil
	}
}

func elaborateCall(list List, f *fiber) (Sexp, Error) {
	if head, ok := list.First().(Symbol); ok {
		switch head {
		case "def":
			return elaborateDef(list, f)
		}
	}

	defer f.pop()

	for i, elem := range list.Elements {
		f.push(elem, i, opElaborate)
		elaborated, err := f.elaborate(elem)
		if err != nil {
			return nil, err
		}
		list.Elements[i] = elaborated
	}

	return list, nil
}

// represents the following [pos1 pos2 ...var {:kwarg default-value}]
type Arity struct {
	Positional []string
	Variadic   string
	Kwargs     []KwargDef
	original   Sexp
}

type KwargDef struct {
	Name    string
	Default Sexp
}

func (k KwargDef) String() string {
	return ":" + k.Name + " " + k.Default.String()
}

func (a Arity) Type() string { return "arity" }
func (a Arity) String() string {
	if a.original != nil {
		return a.original.String()
	}

	s := "["
	numPos := len(a.Positional)
	for _, p := range a.Positional[:numPos-1] {
		s += p + " "
	}
	s += a.Positional[numPos-1]

	if a.Variadic != "" {
		s += " ..." + a.Variadic + " "
	}

	numKwargs := len(a.Kwargs)
	if numKwargs > 0 {
		s += "{"
		for _, k := range a.Kwargs[:numKwargs-1] {
			s += k.String() + " "
		}
		s += a.Kwargs[numKwargs-1].String()
		s += "}"
	}
	return s + "]"
}

func (a Arity) MinArgs() int {
	return len(a.Positional)
}

func (a Arity) MaxArgs() int {
	if a.Variadic != "" {
		return -1
	}
	max := len(a.Positional)
	if len(a.Kwargs) > 0 {
		max++
	}
	return max
}

func (a Arity) AcceptsKwargs() bool {
	return len(a.Kwargs) > 0
}

func (a Arity) Matches(args []Sexp) bool {
	argCount := len(args)
	if a.MinArgs() > argCount {
		return false
	}

	maxArgs := a.MaxArgs()
	if maxArgs < argCount && maxArgs >= 0 { // too many args
		return false
	}

	// if more than positional and kwargs requried, last arg must be map
	if a.AcceptsKwargs() && argCount > len(a.Positional) {
		if _, ok := args[argCount-1].(Map); !ok {
			return false
		}
	}

	return true
}

type defExpr struct {
	name    string
	binding Sexp
}

func (d defExpr) Type() string   { return "def-expression" }
func (d defExpr) String() string { return "(def " + d.name + " " + d.binding.String() + ")" }

var defArity = Arity{
	Positional: []string{"name", "binding"},
}

func elaborateDef(list List, f *fiber) (defExpr, Error) {
	if !defArity.Matches(list.Elements[1:]) {
		return defExpr{}, f.newErrArity("def", defArity, list.Elements[1:])
	}

	name, ok := list.Elements[1].(Symbol)
	if !ok {
		defer f.pop()
		f.push(list.First(), 1, opElaborate)
		return defExpr{}, f.newErrElaborationSyntax("def expects a symbol as it's first argument")
	}

	binding := list.Elements[2]
	def := defExpr{name: string(name), binding: binding}
	return def, nil
}

func elaborateArity(sexp Sexp, f *fiber) (Arity, Error) {
	vector, ok := sexp.(Vector)
	if !ok {
		return Arity{}, f.newErrElaborationAritySyntax("arity expects to be a vector")
	}

	arity := Arity{original: sexp}

	i := 0
	params := vector.Elements

PositionalLoop:
	for i < len(params) {
		switch p := params[i].(type) {
		case Symbol:
			sym := string(p)
			if strings.HasPrefix(sym, "...") {
				if len(sym) == 3 {
					defer f.pop()
					f.push(p, i, opElaborate)
					return Arity{}, f.newErrElaborationAritySyntax("variadic must have a body after the ellipsis")
				}
				arity.Variadic = sym[3:]
				break PositionalLoop
			}
			arity.Positional = append(arity.Positional, string(p))
		case Map:
			break PositionalLoop
		default:
			defer f.pop()
			f.push(p, i, opElaborate)
			return Arity{}, f.newErrElaborationAritySyntax("unexpected arity syntax")
		}
		i++
	}

	if i == len(params)-1 {
		return arity, nil
	}

	kwargs, ok := params[i].(Map)
	if !ok {
		f.push(params[i], i, opElaborate)
		defer f.pop()
		return Arity{}, f.newErrElaborationAritySyntax("arity expects a map for named params")
	}

	for key, value := range kwargs.Elements {
		arity.Kwargs = append(arity.Kwargs, KwargDef{key, value})
	}

	// check if anything else
	i++
	if len(params)-1 > i {
		f.push(params[i], i, opElaborate)
		defer f.pop()
		return Arity{}, f.newErrElaborationAritySyntax("arity expects to end after named args")
	}

	return arity, nil
}
