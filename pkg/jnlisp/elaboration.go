package jnlisp

import (
	"strings"
)

func (f *fiber) elaborate(sexp Sexp, idx int) (Sexp, Error) {
	f.push(sexp, idx, opElaborate)
	defer f.pop()

	switch s := sexp.(type) {
	case List:
		if s.Length() == 0 {
			return nil, f.newErrElaborationSyntax("cannot evaluate the empty list")
		}
		return elaborateCall(s, f)
	case Vector:
		for i, elem := range s.Elements {
			elaborated, err := f.elaborate(elem, i)
			if err != nil {
				return nil, err
			}
			s.Elements[i] = elaborated
		}
		return s, nil
	case Map:
		for i, key := range s.order {
			value := s.Get(key)
			elaborated, err := f.elaborate(value, i*2)
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

	for i, elem := range list.Elements {
		elaborated, err := f.elaborate(elem, i)
		if err != nil {
			return nil, err
		}
		list.Elements[i] = elaborated
	}

	return list, nil
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
