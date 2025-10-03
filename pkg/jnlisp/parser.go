package jnlisp

import (
	"strconv"
	"strings"
)

// doesn't expect any markdown block stuff in between - only s-exps
func parseREPL(tokens []token) (blocks []any, errors []Error) {
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenList {
			ast, syntaxErrs := parseCode(tokens, &idx)
			blocks = append(blocks, ast)
			errors = append(errors, syntaxErrs...)
		} else {
			idx++ // skipping unexpected tokens
		}
	}

	return blocks, errors
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

// PARSING CODE

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
func parseCode(tokens []token, idx *int) (result any, errors []Error) {
	if *idx >= len(tokens) {
		return result, errors
	}

	token := tokens[*idx]
	*idx++

	switch token.typ {
	case tokenOpenList:
		result, errors = parseList(tokens, idx)
	case tokenOpenVec:
		result, errors = parseVector(tokens, idx)
	case tokenOpenTable:
		result, errors = parseTable(tokens, idx)
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

func parseList(tokens []token, idx *int) (list listRaw, errors []Error) {
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

		childExp, childErrors := parseCode(tokens, idx)
		errors = append(errors, childErrors...)
		if childExp != nil {
			list = append(list, childExp)
		}
	}

	return list, errors
}

func parseVector(tokens []token, idx *int) (vec vectorRaw, errors []Error) {
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

		childExp, childErrors := parseCode(tokens, idx)
		errors = append(errors, childErrors...)
		if childExp != nil {
			vec = append(vec, childExp)
		}
	}

	return vec, errors
}

func parseTable(tokens []token, idx *int) (table tableRaw, errors []Error) {
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

		childExp, childErrors := parseCode(tokens, idx)
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
		return float64(f)
	}

	i, _ := strconv.Atoi(t)
	return i
}
