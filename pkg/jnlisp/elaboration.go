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
		case "fn":
			return elaborateFn(list, f)
		case "if":
			return elaborateIf(list, f)
		case "do":
			return elaborateDo(list)
		case "quote":
			return elaborateQuote(list, f)
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

var defArity = Arity{Positional: []string{"name", "binding"}}

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

type fnExpr struct {
	arity Arity
	body  Sexp
}

func (f fnExpr) Type() string { return "fn-expression" }
func (f fnExpr) String() string {
	acc := strings.Builder{}
	acc.WriteString("(fn ")
	acc.WriteString(f.arity.String())
	acc.WriteString(" ")
	acc.WriteString(f.body.String())
	acc.WriteString(")")
	return acc.String()
}

var fnArity = Arity{Positional: []string{"arity"}, Variadic: "body"}

func elaborateFn(list List, f *fiber) (fnExpr, Error) {
	if !fnArity.Matches(list.Elements[1:]) {
		return fnExpr{}, f.newErrArity("fn", fnArity, list.Elements[1:])
	}

	arity, err := elaborateArity(list.Elements[1], f)
	if err != nil {
		return fnExpr{}, nil
	}

	if len(list.Elements[2:]) == 0 {
		return fnExpr{arity, Nil{}}, nil
	}

	if len(list.Elements[2:]) == 1 {
		return fnExpr{arity, list.Elements[2]}, nil
	}

	// multiple body forms - wrap in a doExpr
	body := doExpr{list.Elements[2:]}
	return fnExpr{arity, body}, nil
}

type ifExpr struct {
	predicate   Sexp
	conseq      Sexp
	alternative Sexp
}

func (i ifExpr) Type() string { return "if-expression" }
func (i ifExpr) String() string {
	acc := strings.Builder{}
	acc.WriteString("(if ")
	acc.WriteString(strings.Join([]string{
		i.predicate.String(),
		i.conseq.String(),
		i.alternative.String(),
	}, " "))
	acc.WriteString(")")
	return acc.String()
}

var ifArity = Arity{Positional: []string{"pred", "conseq", "altern"}}

func elaborateIf(list List, f *fiber) (ifExpr, Error) {
	if !ifArity.Matches(list.Elements[1:]) {
		return ifExpr{}, f.newErrArity("if", ifArity, list.Elements[1:])
	}

	pred, err := f.elaborate(list.Elements[1], 1)
	if err != nil {
		return ifExpr{}, err
	}

	conseq, err := f.elaborate(list.Elements[2], 2)
	if err != nil {
		return ifExpr{}, err
	}

	altern, err := f.elaborate(list.Elements[3], 3)
	if err != nil {
		return ifExpr{}, err
	}

	return ifExpr{pred, conseq, altern}, nil
}

type doExpr struct {
	exps []Sexp
}

func (d doExpr) Type() string { return "do-expression" }
func (d doExpr) String() string {
	exps := make([]string, 0, len(d.exps))
	for _, exp := range d.exps {
		exps = append(exps, exp.String())
	}
	acc := strings.Builder{}
	acc.WriteString("(do ")
	acc.WriteString(strings.Join(exps, " "))
	acc.WriteString(")")
	return acc.String()
}

func elaborateDo(list List) (doExpr, Error) {
	if len(list.Elements) == 0 {
		return doExpr{exps: []Sexp{Nil{}}}, nil
	}

	exps := make([]Sexp, 0, len(list.Elements)-1)
	exps = append(exps, list.Elements[1:]...)
	return doExpr{exps}, nil
}

type quoteExpr struct {
	sexp Sexp
}

func (q quoteExpr) Type() string   { return "quote-expression" }
func (q quoteExpr) String() string { return q.sexp.String() }

var quoteArity = Arity{Positional: []string{"exp"}}

func elaborateQuote(list List, f *fiber) (quoteExpr, Error) {
	if !quoteArity.Matches(list.Elements[1:]) {
		return quoteExpr{}, f.newErrArity("quote", ifArity, list.Elements[1:])
	}

	return quoteExpr{sexp: list.Elements[1]}, nil
}

func elaborateArity(sexp Sexp, f *fiber) (Arity, Error) {
	f.push(sexp, 1, opElaborate)
	defer f.pop()

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
					return Arity{}, f.newErrElaborationAritySyntax("variadic must have a body after the ellipsis")
				}
				arity.Variadic = sym[3:]
				break PositionalLoop
			}
			arity.Positional = append(arity.Positional, string(p))
		case Map:
			break PositionalLoop
		default:
			return Arity{}, f.newErrElaborationAritySyntax("unexpected arity syntax")
		}
		i++
	}

	if i == len(params) {
		return arity, nil
	}

	kwargs, ok := params[i].(Map)
	if !ok {
		return Arity{}, f.newErrElaborationAritySyntax("arity expects a map for named params")
	}

	for key, value := range kwargs.Elements {
		arity.Kwargs = append(arity.Kwargs, KwargDef{key, value})
	}

	// check if anything else
	i++
	if len(params)-1 > i {
		return Arity{}, f.newErrElaborationAritySyntax("arity expects to end after named args")
	}

	return arity, nil
}
