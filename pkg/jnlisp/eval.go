package jnlisp

import (
	"fmt"
	"strings"
)

// EVAL IMPLEMENTATION

func eval(expr any, ctx *Context) (Atom, error) {
	switch v := expr.(type) {
	case Atom:
		// already evaluated, return as-is
		return v, nil

	case list:
		return evalList(v, ctx)

	case vector:
		elements := make([]Atom, len(v))
		for i, elem := range v {
			evaluated, err := eval(elem, ctx)
			if err != nil {
				return nil, fmt.Errorf("vector element %d > %w", i, err)
			}
			elements[i] = evaluated
		}
		return VectorAtom{elements}, nil

	case symbol:
		symbolName := string(v)

		if ctx.importPrefix != "" {
			prefixedName := ctx.importPrefix + "/" + symbolName
			if atom, exists := ctx.env.find(prefixedName); exists {
				return atom, nil
			}
		}

		if atom, exists := ctx.env.find(symbolName); exists {
			return atom, nil
		}
		return nil, fmt.Errorf("undefined symbol: %s", v)

	case string:
		return StringAtom{v}, nil

	case int, float32, float64, complex64, complex128:
		return NumberAtom{v}, nil

	case bool:
		return BooleanAtom{v}, nil

	default:
		return nil, fmt.Errorf("unknown expression type %T", expr)
	}
}

func evalList(list list, ctx *Context) (Atom, error) {
	if len(list) == 0 {
		return nil, fmt.Errorf("empty list cannot be evaluated")
	}

	// special forms
	if sym, ok := list[0].(symbol); ok {
		switch sym {
		case "if":
			return evalIf(list, ctx)
		case "define":
			return evalDefine(list, ctx)
		case "lambda":
			return evalLambda(list, ctx)
		case "import":
			return evalImport(list, ctx)
		case "and":
			return evalAnd(list, ctx)
		case "or":
			return evalOr(list, ctx)
		}
	}

	return evalApplication(list, ctx)
}

// SPECIAL FORMS

func evalIf(list list, ctx *Context) (Atom, error) {
	if len(list) != 4 {
		return nil, fmt.Errorf("if expects exactly 3 arguments (test consequence alternative), got %d", len(list)-1)
	}

	test, conseq, alt := list[1], list[2], list[3]
	testResult, err := eval(test, ctx)
	if err != nil {
		return nil, err
	}

	boolean, ok := testResult.(BooleanAtom)
	if !ok {
		return nil, fmt.Errorf("if expects to test a boolean, cannot test %s", testResult.Type())
	}

	if boolean.Value {
		return eval(conseq, ctx)
	} else {
		return eval(alt, ctx)
	}
}

func evalDefine(l list, ctx *Context) (Atom, error) {
	if varName, ok := l[1].(symbol); ok {
		// handle variable
		if len(l) != 3 {
			return nil, fmt.Errorf("define (variable) expects exactly 2 arguments (symbol expression), got %d",
				len(l)-1)
		}

		defExp := l[2]
		defExpResult, err := eval(defExp, ctx)
		if err != nil {
			return nil, err
		}

		bindName := string(varName)
		if ctx.importPrefix != "" {
			bindName = ctx.importPrefix + "/" + bindName
		}
		return ctx.env.bind(bindName, defExpResult), nil
	}

	// handle function definition
	if funcDef, ok := l[1].(list); ok {
		funcName, ok := funcDef[0].(symbol)
		if !ok {
			return nil, fmt.Errorf("define (procedure) expects symbol as first parameter in parameter list, got %T",
				funcDef[0])
		}

		paramList, err := parseParamList(funcDef[1:])
		if err != nil {
			return nil, fmt.Errorf("define (procedure) > %w", err)
		}

		body := l[2:]
		if len(body) == 0 {
			return nil, fmt.Errorf("define (procedure) body cannot be empty")
		}

		proc := &Procedure{
			name:         string(funcName),
			params:       paramList,
			body:         body,
			closure:      ctx.env,
			definingCtx:  ctx,
			importPrefix: ctx.importPrefix,
		}

		bindName := string(funcName)
		if ctx.importPrefix != "" {
			bindName = ctx.importPrefix + "/" + bindName
		}

		return ctx.env.bind(bindName, ProcedureAtom{proc}), nil
	}

	// handle error
	return nil, fmt.Errorf("define expects parameter list (procedure) or symbol (variable) as arg 0 but got %T",
		l[1])
}

func evalLambda(l list, ctx *Context) (Atom, error) {
	if len(l) != 3 {
		return nil, fmt.Errorf("lambda expects exactly 2 args ((params) expression), got %d", len(l)-1)
	}

	paramList, err := parseParamList(l[1:])
	if err != nil {
		return nil, fmt.Errorf("lambda > %w", err)
	}

	body := l[2:] // the rest
	if len(body) == 0 {
		return nil, fmt.Errorf("lambda expects body expression(s) but was empty")
	}

	proc := &Procedure{
		name:         "lambda",
		params:       paramList,
		body:         body,
		closure:      ctx.env,
		definingCtx:  ctx,
		importPrefix: ctx.importPrefix,
	}

	return ProcedureAtom{proc}, nil
}

func evalImport(list list, ctx *Context) (Atom, error) {
	if len(list) != 2 && len(list) != 3 {
		return nil, fmt.Errorf("import expects 1 or 2 arguments")
	}

	libName, ok := list[1].(string)
	if !ok {
		return nil, fmt.Errorf("import expects library name as string")
	}

	prefix := libName // Default prefix
	if len(list) == 3 {
		if prefixArg, ok := list[2].(string); ok {
			prefix = prefixArg
		} else {
			return nil, fmt.Errorf("import prefix must be string")
		}
	}

	return BooleanAtom{true}, ctx.ImportLibrary(libName, prefix)
}

func evalAnd(list list, ctx *Context) (Atom, error) {
	for i := 1; i < len(list); i++ {
		result, err := eval(list[i], ctx)
		if err != nil {
			return nil, err
		}

		boolean, ok := result.(BooleanAtom)
		if !ok {
			return nil, fmt.Errorf("and expects boolean arguments, got %s at position %d",
				result.Type(), i-1)
		}

		if !boolean.Value {
			return BooleanAtom{false}, nil
		}
	}

	return BooleanAtom{true}, nil
}

func evalOr(list list, ctx *Context) (Atom, error) {
	for i := 1; i < len(list); i++ {
		result, err := eval(list[i], ctx)
		if err != nil {
			return nil, err
		}

		boolean, ok := result.(BooleanAtom)
		if !ok {
			return nil, fmt.Errorf("or expects boolean arguments, got %T at position %d", result, i-1)
		}

		if boolean.Value {
			return BooleanAtom{true}, nil
		}
	}

	return BooleanAtom{false}, nil
}

// NORMAL PROCEDURES

func evalApplication(list list, ctx *Context) (Atom, error) {
	keywordIdx := findFirstKeyword(list)

	proc, err := eval(list[0], ctx)
	if err != nil {
		return nil, err
	}

	castProc, ok := As[ProcedureAtom](proc)
	if !ok {
		return nil, fmt.Errorf("cannot call non-procedure: %s", proc.Type())
	}

	if keywordIdx == -1 {
		// No keywords - regular call
		args := make([]Atom, len(list)-1)
		for i := 1; i < len(list); i++ {
			args[i-1], err = eval(list[i], ctx)
			if err != nil {
				return nil, fmt.Errorf("%s parsing args > %w", castProc.name, err)
			}
		}

		return castProc.Call(args, make(Table), ctx)
	}
	// keywords present
	positionalExpr := list[1:keywordIdx]
	keywordSection := list[keywordIdx:]

	if (len(keywordSection) % 2) != 0 {
		return nil, fmt.Errorf("%s parsing args > badly-formed keyword args, expected even number of terms (:key value) but got %d",
			castProc.name, len(keywordSection))
	}

	args := make([]Atom, len(positionalExpr))
	for i, expr := range positionalExpr {
		arg, err := eval(expr, ctx)
		if err != nil {
			return nil, fmt.Errorf("%s parsing args > %w", castProc.name, err)
		}
		args[i] = arg
	}

	// build a table from keywords
	kwargs := make(Table)
	for i := 0; i < len(keywordSection); i += 2 {
		key, ok := keywordSection[i].(keyword)
		if !ok {
			return nil, fmt.Errorf("%s parsing args > badly-formed keyword args, expected keyword at position %d, got %T",
				castProc.name, i+len(positionalExpr), keywordSection[i])
		}

		value, err := eval(keywordSection[i+1], ctx)
		if err != nil {
			return nil, fmt.Errorf("%s parsing args > %w", castProc.name, err)
		}

		kwargs[string(key)] = value
	}

	return castProc.Call(args, kwargs, ctx)
}

// HELPERS

func parseParamList(paramExpr list) (paramList, error) {
	var params paramList

	ampersandEncountered := false
	for i, param := range paramExpr {
		sym, ok := param.(symbol)
		if !ok {
			return params, fmt.Errorf("expects symbols as parameters but got %T at position %d", param, i)
		}

		if sym == symbol("&") {
			ampersandEncountered = true
			continue
		}

		if !ampersandEncountered {
			params.positional = append(params.positional, sym)
		} else {
			params.named = append(params.named, sym)
		}
	}

	return params, nil
}

func findFirstKeyword(l list) int {
	for i, exp := range l {
		if _, ok := exp.(keyword); ok {
			return i
		}
	}
	return -1
}

// ATOMS (eval turns []any into Atom)

type Atom interface {
	fmt.Stringer
	Type() string
	ToJSON() map[string]any
}

type NumberAtom struct{ Value any }

func (n NumberAtom) Type() string   { return "number" }
func (n NumberAtom) String() string { return fmt.Sprintf("%v", n.Value) }
func (n NumberAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  "number",
		"value": n.Value,
		"repr":  n.String(),
	}
}

func (n NumberAtom) ToFloat64() (float64, error) {
	switch v := n.Value.(type) {
	case float64:
		return v, nil
	case float32:
		return float64(v), nil
	case int:
		return float64(v), nil
	default:
		return 0, fmt.Errorf("cannot convert %T to float64", v)
	}
}

type BooleanAtom struct{ Value bool }

func (b BooleanAtom) Type() string { return "boolean" }
func (b BooleanAtom) String() string {
	if b.Value {
		return "#t"
	} else {
		return "#f"
	}
}
func (b BooleanAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  "boolean",
		"value": b.Value,
		"repr":  b.String(),
	}
}

type StringAtom struct{ Value string }

func (s StringAtom) Type() string   { return "string" }
func (s StringAtom) String() string { return s.Value }
func (s StringAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  "string",
		"value": s.Value,
		"repr":  s.String(),
	}
}

type ProcedureAtom struct{ *Procedure }

func (p ProcedureAtom) Type() string { return "procedure" }
func (p ProcedureAtom) String() string {
	// TODO: maybe add a pretty print of params
	return fmt.Sprintf("#<procedure:%s>", p.name)
}

func (p ProcedureAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  "procedure",
		"value": p.name,
		"repr":  p.String(),
	}
}

type VectorAtom struct{ Elements []Atom }

func (v VectorAtom) Type() string { return "vector" }
func (v VectorAtom) String() string {
	var parts []string
	for _, elem := range v.Elements {
		parts = append(parts, elem.String())
	}
	return "[" + strings.Join(parts, " ") + "]"
}
func (v VectorAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  v.Type(),
		"value": v.String(),
		"repr":  v.String(),
	}
}

func (v VectorAtom) Length() int {
	return len(v.Elements)
}

// WRAPPER TYPE FOR QUERYING ENV

type boundAtom struct {
	Atom
	handle string
	env    *env
}

func (b boundAtom) ToJSON() map[string]any {
	json := b.Atom.ToJSON()
	json["handle"] = b.handle
	if b.env != nil {
		json["bound"] = true
	}
	return json
}

func (b boundAtom) Type() string   { return b.Atom.Type() }
func (b boundAtom) String() string { return b.Atom.String() }

func As[T Atom](atom Atom) (T, bool) {
	var zero T
	atom = UnwrapAtom(atom)

	if result, ok := (atom).(T); ok {
		return result, true
	}

	return zero, false
}

func UnwrapAtom(atom Atom) Atom {
	if boundAtom, ok := atom.(boundAtom); ok {
		return boundAtom.Atom
	}
	return atom
}
