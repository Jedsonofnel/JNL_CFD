package jnlisp

import (
	"strconv"
	"strings"
)

// basic types
type symbol string
type keyword string
type list []any
type vector []any

func newSymbol(s string) symbol   { return symbol(s) }
func newKeyword(s string) keyword { return keyword(s) }

// ERROR TYPES

type SyntaxError struct {
	Token   token  `json:"token"`
	Message string `json:"message"`
}

func (e SyntaxError) Error() string {
	return "Syntax error at " + e.Token.pos.String() + ": " + e.Message
}

func newSyntaxErrorFromToken(t token) SyntaxError {
	var message string
	switch t.typ {
	case tokenMissingCloseList:
		message = "missing closing list parenthesis"
	case tokenMissingCloseVec:
		message = "missing closing vector bracket"
	case tokenMissingCloseString:
		message = "missing closing string double quotation mark"
	case tokenMalformedNumber:
		message = "malformed number: " + t.val
	case tokenInvalidLiteral:
		message = "invalid literal: " + t.val
	default:
		panic("Called newSyntaxError with non-error type: " + t.typ.String())
	}

	return SyntaxError{t, message}
}

func newUnexpectedClosingTokenError(t token) SyntaxError {
	return SyntaxError{
		Token:   t,
		Message: "unexpected '" + t.val + "'",
	}
}

func newUnexpectedTokenError(t token) SyntaxError {
	return SyntaxError{
		Token:   t,
		Message: "unexpected token '" + t.String() + "', value: " + t.val,
	}
}

// doesn't expect any markdown block stuff in between - only s-exps
func parseREPL(tokens []token) []ParseExprResult {
	var expressions []ParseExprResult
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenList {
			result := parseExpression(tokens, &idx)
			expressions = append(expressions, result)
		} else {
			idx++ // skipping unexpected tokens
		}
	}

	return expressions
}

type srcPosition struct {
	startPos Pos
	endPos   Pos
}

func parseSrc(tokens []token) ([]ParseExprResult, []srcPosition) {
	var expressions []ParseExprResult
	var srcPositions []srcPosition
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenList {
			pos := srcPosition{startPos: tokens[idx].pos}

			result := parseExpression(tokens, &idx)

			expressions = append(expressions, result)
			pos.endPos = tokens[idx-1].pos
			srcPositions = append(srcPositions, pos)
		} else {
			idx++ // skipping anything between top level s-exps
		}
	}

	return expressions, srcPositions
}

// PARSING EXPRESSIONS

type ParseExprResult struct {
	Expr   any
	Errors []SyntaxError
}

func parseExpression(tokens []token, idx *int) (result ParseExprResult) {
	if *idx >= len(tokens) {
		return result
	}

	token := tokens[*idx]
	*idx++

	switch token.typ {
	case tokenOpenList:
		var list list
		for *idx < len(tokens) {
			if tokens[*idx].typ == tokenCloseList {
				*idx++
				break
			}

			if tokens[*idx].typ == tokenMissingCloseList {
				result.Errors = append(result.Errors, newSyntaxErrorFromToken(tokens[*idx]))
				*idx++
				break
			}

			child := parseExpression(tokens, idx)
			result.Errors = append(result.Errors, child.Errors...)
			if child.Expr != nil {
				list = append(list, child.Expr)
			}
		}

		result.Expr = list
		return result

	case tokenOpenVec:
		var vec vector
		for *idx < len(tokens) {
			if tokens[*idx].typ != tokenCloseVec {
				*idx++
				break
			}

			if tokens[*idx].typ == tokenMissingCloseVec {
				result.Errors = append(result.Errors, newSyntaxErrorFromToken(tokens[*idx]))
				*idx++
				break
			}

			child := parseExpression(tokens, idx)
			result.Errors = append(result.Errors, child.Errors...)
			if child.Expr != nil {
				vec = append(vec, child.Expr)
			}
		}

		result.Expr = vec
		return result

	case tokenCloseList, tokenCloseVec:
		result.Errors = append(result.Errors, newUnexpectedClosingTokenError(token))
		return result

	case tokenNumber:
		result.Expr = parseNumber(token.val)
		return result

	case tokenString:
		result.Expr = token.val
		return result

	case tokenBool:
		result.Expr = parseBool(token.val)
		return result

	case tokenSymbol:
		result.Expr = newSymbol(token.val)
		return result

	case tokenKeyword:
		result.Expr = newKeyword(token.val)
		return result

	case tokenMissingCloseList,
		tokenMissingCloseVec,
		tokenMissingCloseString,
		tokenMalformedNumber,
		tokenInvalidLiteral:
		result.Errors = append(result.Errors, newSyntaxErrorFromToken(token))
		return result

	default:
		result.Errors = append(result.Errors, newUnexpectedTokenError(token))
		return result
	}
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
