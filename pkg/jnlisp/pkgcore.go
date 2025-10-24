package jnlisp

var corePkg = &Package{
	Name: "core",
	Bindings: map[string]Sexp{
		"+": lispAdd,
	},
}

var lispAdd = MultiArityNative{
	name:    "+",
	arities: addArities,
	fns:     []CallableFunc{addNilArity, addOneArity},
}

var addArities = MultiArity{
	Arity{},
	Arity{Positional: []string{"a"}},
}

var addNilArity = func(args []Sexp, _ *fiber) (Sexp, Error) {
	return Int(0), nil
}

var addOneArity = func(args []Sexp, f *fiber) (Sexp, Error) {
	av := ValidateArgs(args, addArities[1], f, "+")
	a := GetArg[Number](av)
	if err := av.Validate(); err != nil {
		return Nil{}, err
	}

	return a, nil
}
