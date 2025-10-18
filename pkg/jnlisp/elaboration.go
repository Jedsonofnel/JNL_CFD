package jnlisp

func elaborate(raw any) (expr, Error) {
	switch r := raw.(type) {
	case symbol:
		return symbolExpr{string(r)}, nil
	case listRaw:
		if len(r) == 0 {
			return nil, ElaborationError{
				Message: "cannot evaluate empty list ()",
			}
		}
		return elaborateCall(r)
	case vectorRaw:
		return elaborateVector(r)
	case tableRaw:
		return elaborateTable(r)
	case bool, int, float32, float64, complex128, string, keyword:
		return literalExpr{r}, nil
	default:
		panic("UNEXPECTED ELABORATION TYPE")
	}
}

func elaborateCall(list listRaw) (expr, Error) {
	switch head := list[0].(type) {
	case symbol:
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

		headExpr, err := elaborate(list[0])
		args, kwargs, err := elaborateArgs(list[1:])
		if err != nil {
			return nil, err
		}
		return callExpr{headExpr, args, kwargs}, nil
	case callExpr:
		headExpr, err := elaborate(list[0])
		args, kwargs, err := elaborateArgs(list[1:])
		if err != nil {
			return nil, err
		}
		return callExpr{headExpr, args, kwargs}, nil
	default:
		return nil, ElaborationError{
			Message: "list expects a function at head to evaluate",
		}
	}
}

func elaborateVector(vector vectorRaw) (vectorExpr, Error) {
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

func elaborateTable(table tableRaw) (tableExpr, Error) {
	if len(table)%2 != 0 {
		return tableExpr{}, ElaborationError{
			Message: "table literal expects an even number of elements (key-value pairs)",
		}
	}

	elements := make(map[string]expr)

	for i := 0; i < len(table); i += 2 {
		key, ok := table[i].(keyword)
		if !ok {
			return tableExpr{}, ElaborationError{
				Message: "table key must be a :keyword",
			}
		}

		expr, err := elaborate(table[i+1])
		if err != nil {
			return tableExpr{}, err
		}

		elements[string(key)] = expr
	}

	return tableExpr{elements}, nil
}

func elaborateArgs(list listRaw) (args []expr, kwargs tableExpr, err Error) {
	args = make([]expr, 0)
	kwargMap := make(map[string]expr)

	i := 0
	for i < len(list) {
		if _, ok := list[i].(keyword); ok {
			break // start parsing table
		}

		arg, err := elaborate(list[i])
		if err != nil {
			return args, kwargs, err
		}
		args = append(args, arg)
		i++
	}

	remainingArgs := make(tableRaw, len(list)-i)
	copy(remainingArgs, list[i:])

	kwargs, err = elaborateTable(remainingArgs)
	if err != nil {
		return args, kwargs, err
	}

	kwargs = tableExpr{kwargMap}
	return args, kwargs, nil
}

// SPECIAL FORM ELABORATION

func elaborateDefine(args listRaw) (defineExpr, Error) {
	if len(args) != 2 {
		return defineExpr{}, ElaborationError{
			Message: "define expects 2 arguments (symbol binding)",
		}
	}

	sym, ok := args[0].(symbol)
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

func elaborateLambda(args listRaw) (lambdaExpr, Error) {
	if len(args) != 2 {
		return lambdaExpr{}, ElaborationError{
			Message: "lambda expects 2 arguments ((arguments...) body)",
		}
	}

	argsList, ok := args[0].(listRaw)
	if !ok {
		return lambdaExpr{}, ElaborationError{
			Message: "lambda expects a list as its first argument",
		}
	}

	// get all the lambda arguments as symbols
	allArgs := make([]symbol, len(argsList))

	for i := range argsList {
		if sym, ok := argsList[i].(symbol); ok {
			allArgs[i] = sym
			continue
		}
		return lambdaExpr{}, ElaborationError{
			Message: "lambda expects function arguments to be symbols",
		}
	}

	// then split them if there's an ampersand
	var positionalArgs []symbol
	var kwargs []symbol

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

func elaborateIf(args listRaw) (ifExpr, Error) {
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

func elaborateBegin(args listRaw) (beginExpr, Error) {
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

func elaborateSetBang(args listRaw) (setBangExpr, Error) {
	if len(args) != 2 {
		return setBangExpr{}, ElaborationError{
			Message: "set! expects 2 arguments (name binding)",
		}
	}

	sym, ok := args[0].(symbol)
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

func elaborateImport(args listRaw) (importExpr, Error) {
	if !(len(args) == 2 || len(args) == 1) {
		return importExpr{}, ElaborationError{
			Message: "import expects 1 or 2 arguments (library-name prefix)",
		}
	}

	libraryName, ok := args[0].(string)
	if !ok {
		return importExpr{}, ElaborationError{
			Message: "import expects a string for its first argument",
		}
	}

	prefix := libraryName
	if len(args) == 2 {
		prefix, ok = args[1].(string)
		if !ok {
			return importExpr{}, ElaborationError{
				Message: "import expects a string for its optional second argument",
			}
		}
	}

	return importExpr{libraryName, prefix}, nil
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
	value any
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
	quoted expr
}

func (q quotedExpr) expr() {}

// SPECIAL FORMS

type defineExpr struct {
	name    symbol
	binding expr
}

func (de defineExpr) expr() {}

type lambdaExpr struct {
	args   []symbol
	kwargs []symbol
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
	name    symbol
	binding expr
}

func (set setBangExpr) expr() {}

type importExpr struct {
	name   string
	prefix string
}

func (e importExpr) expr() {}
