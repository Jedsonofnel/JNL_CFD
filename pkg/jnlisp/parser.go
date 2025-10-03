package jnlisp

import (
	"strconv"
	"strings"
)

// doesn't expect any markdown block stuff in between - only s-exps
func parseREPL(tokens []token) (exps []any, errors []Error) {
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenList {
			exp, expErrors := parseCode(tokens, &idx)
			exps = append(exps, exp)
			errors = append(errors, expErrors...)
		} else {
			idx++ // skipping unexpected tokens
		}
	}

	return exps, errors
}

func parseDocument(src string, tokens []token) (blocks []Block) {
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		tok := tokens[idx]

		if tok.typ == tokenProse && isWhitespaceOnly(tok.val) {
			idx++
			continue
		}

		b := Block{StartPos: tok.pos}

		switch t := tok.typ; t {
		case tokenProse:
			b.Type = "prose"
			idx++
		case tokenOpenList:
			b.Type = "code"

			expression, errors := parseCode(tokens, &idx)
			b.exp = expression

			// cast []SyntaxError into []Error
			for _, err := range errors {
				b.Errors = append(b.Errors, err)
			}
		default:
			panic("unexpected token type in parseDocument: " + t.String())
		}

		// At this point idx points to the next token
		// EndPos is the start of the next token (which could be EOF)
		b.EndPos = tokens[idx].pos
		b.Content = src[b.StartPos.Offset:b.EndPos.Offset]
		blocks = append(blocks, b)
	}

	return blocks
}

func isWhitespaceOnly(s string) bool {
	return strings.TrimSpace(s) == ""
}

// PARSING EXPRESSIONS

func parseCode(tokens []token, idx *int) (ast any, errors []Error) {
	rawExpr, syntaxErrors := parseRawExpr(tokens, idx)
	errors = append(errors, syntaxErrors...)

	expandedExpr, expansionErrors := expand(rawExpr)
	errors = append(errors, expansionErrors...)

	ast = expandedExpr

	// TODO: pass these threough elaboration to convert to smarter AST

	// TODO: pass through optimisation for block-level optimisations

	return ast, errors
}

// FIRST STAGE - RAW TREE

// basic types used throughout
// string and number are just themselves
type symbol string
type keyword string

func newSymbol(s string) symbol   { return symbol(s) }
func newKeyword(s string) keyword { return keyword(s) }

// compound raw types
type listRaw []any
type vectorRaw []any
type tableRaw []any

type errorRaw struct {
	token token
}

// Creates a tree structure from tokens with no semantic analysis
func parseRawExpr(tokens []token, idx *int) (result any, errors []Error) {
	if *idx >= len(tokens) {
		return result, errors
	}

	token := tokens[*idx]
	*idx++

	switch token.typ {
	case tokenOpenList:
		result, errors = parseRawList(tokens, idx)
	case tokenOpenVec:
		result, errors = parseRawVector(tokens, idx)
	case tokenOpenTable:
		result, errors = parseRawTable(tokens, idx)
	case tokenCloseList, tokenCloseVec, tokenCloseTable: // lexer catches these - shouldn't fire
		errors = append(errors, newUnexpectedClosingTokenError(token))
		result = errorRaw{token}
	case tokenNumber:
		result = parseNumber(token.val)
	case tokenString:
		result = token.val
	case tokenBool:
		result = parseBool(token.val)
	case tokenSymbol:
		result = newSymbol(token.val)
	case tokenKeyword:
		result = newKeyword(token.val)
	case tokenMissingCloseList,
		tokenMissingCloseVec,
		tokenMissingCloseTable,
		tokenMissingCloseString,
		tokenMalformedNumber,
		tokenInvalidLiteral:
		errors = append(errors, newSyntaxErrorFromToken(token))
		result = errorRaw{token}
	default:
		errors = append(errors, newUnexpectedTokenError(token))
		result = errorRaw{token}
	}

	return result, errors
}

func parseRawList(tokens []token, idx *int) (list listRaw, errors []Error) {
	for *idx < len(tokens) {
		if tokens[*idx].typ == tokenCloseList {
			*idx++
			break
		}

		if tokens[*idx].typ == tokenMissingCloseList {
			errors = append(errors, newSyntaxErrorFromToken(tokens[*idx]))
			*idx++
			break
		}

		childExp, childErrors := parseRawExpr(tokens, idx)
		errors = append(errors, childErrors...)
		if childExp != nil {
			list = append(list, childExp)
		}
	}

	return list, errors
}

func parseRawVector(tokens []token, idx *int) (vec vectorRaw, errors []Error) {
	for *idx < len(tokens) {
		if tokens[*idx].typ == tokenCloseVec {
			*idx++
			break
		}

		if tokens[*idx].typ == tokenMissingCloseVec {
			errors = append(errors, newSyntaxErrorFromToken(tokens[*idx]))
			*idx++
			break
		}

		childExp, childErrors := parseRawExpr(tokens, idx)
		errors = append(errors, childErrors...)
		if childExp != nil {
			vec = append(vec, childExp)
		}
	}

	return vec, errors
}

func parseRawTable(tokens []token, idx *int) (table tableRaw, errors []Error) {
	for *idx < len(tokens) {
		if tokens[*idx].typ == tokenCloseTable {
			*idx++
			break
		}

		if tokens[*idx].typ == tokenMissingCloseTable {
			errors = append(errors, newSyntaxErrorFromToken(tokens[*idx]))
			*idx++
			break
		}

		childExp, childErrors := parseRawExpr(tokens, idx)
		errors = append(errors, childErrors...)
		if childExp != nil {
			table = append(table, childExp)
		}
	}

	return table, errors
}

func parseBool(t string) bool {
	if t == "#f" || t == "#F" {
		return false
	}
	return true
}

func parseNumber(t string) any {
	if strings.ContainsAny(t, "ij") {
		c, _ := strconv.ParseComplex(t, 128)
		return c
	}

	if strings.ContainsAny(t, ".eE") {
		f, _ := strconv.ParseFloat(t, 32)
		return float32(f)
	}

	i, _ := strconv.Atoi(t)
	return i
}

// SECOND STAGE - Expansion, still raw

const maxExpansionDepth = 1000

func expand(raw any) (any, []Error) {
	return expandWithDepth(raw, 0)
}

func expandWithDepth(raw any, depth int) (any, []Error) {
	if depth > maxExpansionDepth {
		return raw, []Error{ExpansionError{
			Message: "expansion depth exceeded at " + strconv.Itoa(depth),
			Pos:     Pos{}, // TODO: add pos data to raw parser types
		}}
	}

	switch r := raw.(type) {
	case listRaw:
		if len(r) == 0 {
			return r, nil
		}

		if sym, ok := r[0].(symbol); ok {
			// TODO: recursive macro expansion here

			// built-in expansions
			switch sym {
			case "define":
				expanded, err := expandDefine(r[1:])
				if err != nil {
					return errorRaw{}, []Error{err}
				}
				r = expanded.(listRaw) // fall through to child recursion
			case "let":
				expanded, err := expandLet(r[1:])
				if err != nil {
					return errorRaw{}, []Error{err}
				}
				return expandWithDepth(expanded, depth+1)
			case "and":
				expanded := expandAnd(r[1:])
				return expandWithDepth(expanded, depth+1)
			case "or":
				expanded := expandOr(r[1:], depth)
				return expandWithDepth(expanded, depth+1)
			}
		}

		// not a macro - recurse into children
		result := make(listRaw, len(r))
		var errors []Error
		for i, elem := range r {
			// don't increment depth as this won't loop
			expanded, childErrors := expandWithDepth(elem, depth)
			errors = append(errors, childErrors...)
			result[i] = expanded
		}
		return result, errors
	case vectorRaw:
		result := make(vectorRaw, len(r))
		var errors []Error
		for i, elem := range r {
			expanded, childErrors := expandWithDepth(elem, depth)
			errors = append(errors, childErrors...)
			result[i] = expanded
		}
		return result, errors
	case tableRaw:
		result := make(tableRaw, len(r))
		var errors []Error
		for i, elem := range r {
			expanded, childErrors := expandWithDepth(elem, depth)
			errors = append(errors, childErrors...)
			result[i] = expanded
		}
		return result, errors
	default:
		return raw, nil // most types don't need expansion
	}
}

// BUILT IN EXPANSIONS (will eventually be superseded by macros)

func expandDefine(args listRaw) (any, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "define expects binding details and at least one body expression",
		}
	}

	// early termination if simple lexical binding
	if sym, ok := args[0].(symbol); ok {
		defineSym := listRaw{symbol("define"), sym}
		defineSym = append(defineSym, args[1:]...)
		return defineSym, nil
	}

	funcArgs, ok := args[0].(listRaw)
	if !ok || len(funcArgs) == 0 {
		return nil, ExpansionError{
			Message: "define expects a symbol or a list of symbols as first argument",
		}
	}

	funcSymArgs := make(listRaw, len(funcArgs))

	for i := range funcArgs {
		if sym, ok := funcArgs[i].(symbol); ok {
			funcSymArgs[i] = sym
			continue
		}

		return nil, ExpansionError{
			Message: "define (procedure) expects a list of symbols as first argument",
		}
	}

	lambda := listRaw{symbol("lambda"), funcSymArgs[1:]}
	lambda = append(lambda, args[1:]...)
	defineProc := listRaw{symbol("define"), funcSymArgs[0], lambda}
	return defineProc, nil
}

func expandLet(args listRaw) (any, Error) {
	if len(args) < 2 {
		return nil, ExpansionError{
			Message: "let expects bindings and at least one body expression",
		}
	}

	bindings, ok := args[0].(listRaw)
	if !ok {
		return nil, &ExpansionError{
			Message: "let expects a list of bindings as arg 1",
		}
	}

	names := make(listRaw, 0, len(bindings))
	values := make(listRaw, 0, len(bindings))

	for i := range bindings {
		binding, ok := bindings[i].(listRaw)
		errMsg := "let expects bindings to be (symbol value) pairs"
		if !ok || len(binding) != 2 {
			return nil, &ExpansionError{Message: errMsg}
		}

		name, ok := binding[0].(symbol)
		if !ok {
			return nil, &ExpansionError{Message: errMsg}
		}

		names = append(names, name)
		values = append(values, binding[1])
	}

	lambda := listRaw{symbol("lambda"), names}
	lambda = append(lambda, args[1:]...)

	call := listRaw{lambda}
	call = append(call, values...)

	return call, nil
}

func expandAnd(args listRaw) any {
	if len(args) == 0 {
		return true
	}

	if len(args) == 1 {
		return true
	}

	rest := listRaw{symbol("and")}
	rest = append(rest, args[1:]...)

	// short circuit if it's false
	return listRaw{symbol("if"), args[0], rest, false}
}

func expandOr(args listRaw, depth int) any {
	if len(args) == 0 {
		return false
	}

	if len(args) == 1 {
		return args[0]
	}

	tmpSym := symbol("tmp#" + strconv.Itoa(depth))
	rest := listRaw{symbol("or")}
	rest = append(rest, args[1:]...)

	return listRaw{
		symbol("let"),
		listRaw{listRaw{tmpSym, args[0]}},
		listRaw{symbol("if"), tmpSym, tmpSym, rest},
	}
}

// EXPRESSION TYPES - all corresponding to special forms, loosely based on
// https://groups.csail.mit.edu/mac/ftpdir/scheme-7.4/doc-html/scheme_3.html

type expr interface {
	expr() // just to mark types as valid Expr
}

// CORE DATA TYPES

type callExpr struct {
	elements []expr
}

func (ae callExpr) expr() {}

type listExpr struct {
	elements []expr
}

func (lst listExpr) expr() {}

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

type ifExpr struct {
	predicate expr
	success   expr
	failure   expr
}

func (ie ifExpr) expr() {}

type lambdaExpr struct {
	args      []symbol
	procedure expr
}

func (le lambdaExpr) expr() {}

type beginExpr struct {
	exprs []expr
}

func (be beginExpr) expr() {}

type setBangExpr struct {
	name    symbol
	binding expr
}

func (set setBangExpr) expr() {}
