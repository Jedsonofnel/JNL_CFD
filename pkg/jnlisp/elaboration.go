package jnlisp

func elaborate(sexp Sexp) (expr, Error) {
	switch r := sexp.(type) {
	case Symbol:
		return symbolExpr{string(r)}, nil
	case List:
		if len(r) == 0 {
			return nil, ElaborationError{
				Message: "cannot evaluate empty list ()",
			}
		}
		return elaborateCall(r)
	case Vector:
		return elaborateVector(r)
	case Table:
		return elaborateTable(r)
	case Boolean, Number, String, Keyword:
		return literalExpr{r}, nil
	default:
		panic("UNEXPECTED ELABORATION TYPE")
	}
}

func elaborateCall(list List) (expr, Error) {
	if head, ok := list[0].(Symbol); ok {
		switch head {
		case "define":
			return elaborateDefine(list[1:])
		case "lambda":
			return elaborateLambda(list[1:])
		case "if":
			return elaborateIf(list[1:])
		case "begin":
			return elaborateBegin(list[1:])
		case "set!":
			return elaborateSetBang(list[1:])
		case "import":
			return elaborateImport(list[1:])
		}
	}

	headExpr, err := elaborate(list[0])
	if err != nil {
		return nil, err
	}

	args, kwargs, err := elaborateArgs(list[1:])
	if err != nil {
		return nil, err
	}

	return callExpr{headExpr, args, kwargs}, nil
}

func elaborateVector(vector Vector) (vectorExpr, Error) {
	elements := make([]expr, 0)
	for i := range vector {
		elem, err := elaborate(vector[i])
		if err != nil {
			return vectorExpr{}, err
		}
		elements[i] = elem
	}

	return vectorExpr{elements}, nil
}

func elaborateTable(table Table) (tableExpr, Error) {
	elements := make(map[string]expr)
	for kword, value := range table {
		expr, err := elaborate(value)
		if err != nil {
			return tableExpr{}, err
		}

		elements[kword] = expr
	}

	return tableExpr{elements}, nil
}

func elaborateArgs(list List) (args []expr, kwargs tableExpr, err Error) {
	args = make([]expr, 0)

	i := 0
	for i < len(list) {
		if _, ok := list[i].(Keyword); ok {
			break // start parsing table
		}

		arg, err := elaborate(list[i])
		if err != nil {
			return args, kwargs, err
		}
		args = append(args, arg)
		i++
	}

	// TODO remove this!
	table := make(Table)
	remainingArgs := make(List, len(list)-i)
	copy(remainingArgs, list[i:])

	if len(remainingArgs)%2 != 0 {
		return args, kwargs, ElaborationError{
			"table literal expects an even number of elements (key-value pairs)",
		}
	}

	for i := 0; i < len(remainingArgs); i += 2 {
		key, ok := remainingArgs[i].(Keyword)
		if !ok {
			return args, kwargs, ElaborationError{
				"table key must be a :keyword",
			}
		}

		table[string(key)] = remainingArgs[i+1]
	}

	kwargs, err = elaborateTable(table)
	if err != nil {
		return args, kwargs, err
	}

	return args, kwargs, nil
}

// SPECIAL FORM ELABORATION

func elaborateDefine(args List) (defineExpr, Error) {
	if len(args) != 2 {
		return defineExpr{}, ElaborationError{
			Message: "define expects 2 arguments (symbol binding)",
		}
	}

	sym, ok := args[0].(Symbol)
	if !ok {
		return defineExpr{}, ElaborationError{
			Message: "define expects a symbol as its first argument",
		}
	}

	binding, err := elaborate(args[1])
	if err != nil {
		return defineExpr{}, err
	}

	return defineExpr{sym, binding}, nil
}

func elaborateLambda(args List) (lambdaExpr, Error) {
	if len(args) != 2 {
		return lambdaExpr{}, ElaborationError{
			Message: "lambda expects 2 arguments ((arguments...) body)",
		}
	}

	argsList, ok := args[0].(List)
	if !ok {
		return lambdaExpr{}, ElaborationError{
			Message: "lambda expects a list as its first argument",
		}
	}

	// get all the lambda arguments as symbols
	allArgs := make([]Symbol, len(argsList))

	for i := range argsList {
		if sym, ok := argsList[i].(Symbol); ok {
			allArgs[i] = sym
			continue
		}
		return lambdaExpr{}, ElaborationError{
			Message: "lambda expects function arguments to be symbols",
		}
	}

	// then split them if there's an ampersand
	var positionalArgs []Symbol
	var kwargs []Symbol

	i := 0
	for i < len(argsList) {
		if allArgs[i] == "&" {
			break
		}
		positionalArgs = append(positionalArgs, allArgs[i])
		i++
	}

	for i < len(argsList) {
		kwargs = append(kwargs, allArgs[i])
		i++
	}

	body, err := elaborate(args[1])
	if err != nil {
		return lambdaExpr{}, err
	}

	return lambdaExpr{positionalArgs, kwargs, body}, nil
}

func elaborateIf(args List) (ifExpr, Error) {
	if len(args) != 3 {
		return ifExpr{}, ElaborationError{
			Message: "if expects 3 arguments (predicate consequent alternative)",
		}
	}

	predicate, err := elaborate(args[0])
	if err != nil {
		return ifExpr{}, err
	}

	consequent, err := elaborate(args[1])
	if err != nil {
		return ifExpr{}, err
	}

	alternative, err := elaborate(args[2])
	if err != nil {
		return ifExpr{}, err
	}

	return ifExpr{predicate, consequent, alternative}, nil
}

func elaborateBegin(args List) (beginExpr, Error) {
	exprs := make([]expr, len(args))
	for i := range args {
		bodyExpr, err := elaborate(args[i])
		if err != nil {
			return beginExpr{}, err
		}
		exprs[i] = bodyExpr
	}

	return beginExpr{exprs}, nil
}

func elaborateSetBang(args List) (setBangExpr, Error) {
	if len(args) != 2 {
		return setBangExpr{}, ElaborationError{
			Message: "set! expects 2 arguments (name binding)",
		}
	}

	sym, ok := args[0].(Symbol)
	if !ok {
		return setBangExpr{}, ElaborationError{
			Message: "set! expects a symbol for its first argument",
		}
	}

	binding, err := elaborate(args[1])
	if err != nil {
		return setBangExpr{}, err
	}

	return setBangExpr{sym, binding}, nil
}

func elaborateImport(args List) (importExpr, Error) {
	if !(len(args) == 2 || len(args) == 1) {
		return importExpr{}, ElaborationError{
			Message: "import expects 1 or 2 arguments (library-name prefix)",
		}
	}

	libraryName, ok := args[0].(String)
	if !ok {
		return importExpr{}, ElaborationError{
			Message: "import expects a string for its first argument",
		}
	}

	prefix := libraryName
	if len(args) == 2 {
		prefix, ok = args[1].(String)
		if !ok {
			return importExpr{}, ElaborationError{
				Message: "import expects a string for its optional second argument",
			}
		}
	}

	return importExpr{string(libraryName), string(prefix)}, nil
}

// EXPRESSION TYPES - all corresponding to special forms, loosely based on
// https://groups.csail.mit.edu/mac/ftpdir/scheme-7.4/doc-html/scheme_3.html

type expr interface {
	expr() // just to mark types as valid Expr
}

// CORE DATA TYPES

type callExpr struct {
	fn     expr
	args   []expr
	kwargs tableExpr
}

func (ae callExpr) expr() {}

type symbolExpr struct {
	name string
}

func (e symbolExpr) expr() {}

type literalExpr struct {
	sexp Sexp
}

func (le literalExpr) expr() {}

type vectorExpr struct {
	elements []expr
}

func (v vectorExpr) expr() {}

type tableExpr struct {
	elements map[string]expr
}

func (t tableExpr) expr() {}

type quotedExpr struct {
	quoted Sexp
}

func (q quotedExpr) expr() {}

// SPECIAL FORMS

type defineExpr struct {
	name    Symbol
	binding expr
}

func (de defineExpr) expr() {}

type lambdaExpr struct {
	args   []Symbol
	kwargs []Symbol
	fn     expr
}

func (le lambdaExpr) expr() {}

type ifExpr struct {
	predicate   expr
	consequent  expr
	alternative expr
}

func (ie ifExpr) expr() {}

type beginExpr struct {
	exprs []expr
}

func (be beginExpr) expr() {}

type setBangExpr struct {
	name    Symbol
	binding expr
}

func (set setBangExpr) expr() {}

type importExpr struct {
	name   string
	prefix string
}

func (e importExpr) expr() {}
