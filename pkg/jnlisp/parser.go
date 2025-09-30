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
	token   token
	message string
}

func (e SyntaxError) Error() string {
	return "Syntax error at " + e.token.pos.String() + ": " + e.message
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
		token:   t,
		message: "unexpected '" + t.val + "'",
	}
}

func newUnexpectedTokenError(t token) SyntaxError {
	return SyntaxError{
		token:   t,
		message: "unexpected token '" + t.String() + "', value: " + t.val,
	}
}

// doesn't expect any markdown block stuff in between - only s-exps
func parseREPL(tokens []token) (exps []any, errors []SyntaxError) {
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenList {
			exp, expErrors := parseExpression(tokens, &idx)
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

			exp, errors := parseExpression(tokens, &idx)
			b.exp = exp

			// turn []SyntaxError into []InterpreterError
			for _, err := range errors {
				b.Errors = append(b.Errors, InterpreterError{err.token.pos, err.Error()})
			}

			// pos is really the end position of a token so the end of the last token in
			// this code block is the end of idx-1 (as idx points to the NEXT thing)

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

// PARSING EXPRESSIONS

func parseExpression(tokens []token, idx *int) (exp any, errors []SyntaxError) {
	if *idx >= len(tokens) {
		return exp, errors
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
				errors = append(errors, newSyntaxErrorFromToken(tokens[*idx]))
				*idx++
				break
			}

			childExp, childErrors := parseExpression(tokens, idx)
			errors = append(errors, childErrors...)
			if childExp != nil {
				list = append(list, childExp)
			}
		}

		return list, errors

	case tokenOpenVec:
		var vec vector
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

			childExp, childErrors := parseExpression(tokens, idx)
			errors = append(errors, childErrors...)
			if childExp != nil {
				vec = append(vec, childExp)
			}
		}

		return vec, errors

	case tokenCloseList, tokenCloseVec:
		errors = append(errors, newUnexpectedClosingTokenError(token))

	case tokenNumber:
		exp = parseNumber(token.val)

	case tokenString:
		exp = token.val

	case tokenBool:
		exp = parseBool(token.val)

	case tokenSymbol:
		exp = newSymbol(token.val)

	case tokenKeyword:
		exp = newKeyword(token.val)

	case tokenMissingCloseList,
		tokenMissingCloseVec,
		tokenMissingCloseString,
		tokenMalformedNumber,
		tokenInvalidLiteral:
		errors = append(errors, newSyntaxErrorFromToken(token))

	default:
		errors = append(errors, newUnexpectedTokenError(token))
	}

	return exp, errors
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

func isWhitespaceOnly(s string) bool {
	return strings.TrimSpace(s) == ""
}
