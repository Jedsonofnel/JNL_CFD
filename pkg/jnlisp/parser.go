package jnlisp

import (
	"strconv"
	"strings"
)

func parse(src string, tokens []token) (blocks []Block) {
	idx := 0

	for idx < len(tokens) {
		tok := tokens[idx]

		if tok.typ == tokenEOF {
			break
		}

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
			b.rawAST = expression

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

// Creates a tree structure from tokens with no semantic analysis
func parseCode(tokens []token, idx *int) (sexp Sexp, errors []Error) {
	if *idx >= len(tokens) {
		return sexp, errors
	}

	token := tokens[*idx]
	*idx++

	switch token.typ {
	case tokenOpenList:
		sexp, errors = parseList(tokens, idx)
	case tokenOpenVec:
		sexp, errors = parseVector(tokens, idx)
	case tokenOpenTable:
		sexp, errors = parseTable(tokens, idx)
	case tokenCloseList, tokenCloseVec, tokenCloseTable: // lexer catches these - shouldn't fire
		err := newUnexpectedClosingTokenError(token)
		errors = append(errors, err)
		sexp = err
	case tokenNumber:
		sexp = parseNumber(token.val)
	case tokenString:
		sexp = String(token.val)
	case tokenBool:
		sexp = parseBool(token.val)
	case tokenSymbol:
		sexp = Symbol(token.val)
	case tokenKeyword:
		sexp = Symbol(token.val)
	case tokenMissingCloseList,
		tokenMissingCloseVec,
		tokenMissingCloseTable,
		tokenMissingCloseString,
		tokenMalformedNumber,
		tokenInvalidLiteral,
		tokenUnexpectedCloseList,
		tokenUnexpectedCloseVec,
		tokenUnexpectedCloseTable:
		err := newSyntaxErrorFromToken(token)
		errors = append(errors, err)
		sexp = err
	default:
		err := newUnexpectedTokenError(token)
		errors = append(errors, err)
		sexp = err
	}

	return sexp, errors
}

func parseList(tokens []token, idx *int) (List, []Error) {
	list := List{}
	errors := []Error{}

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

		childSexp, childErrors := parseCode(tokens, idx)
		errors = append(errors, childErrors...)
		if childSexp != nil {
			list = append(list, childSexp)
		}
	}

	return list, errors
}

func parseVector(tokens []token, idx *int) (Vector, []Error) {
	vec := Vector{}
	errors := []Error{}

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

		childSexp, childErrors := parseCode(tokens, idx)
		errors = append(errors, childErrors...)
		if childSexp != nil {
			vec = append(vec, childSexp)
		}
	}

	return vec, errors
}

func parseTable(tokens []token, idx *int) (Sexp, []Error) {
	table := make(Table)
	errors := []Error{}

	firstIndex := *idx
	var tableElements []Sexp
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

		childSexp, childErrors := parseCode(tokens, idx)
		errors = append(errors, childErrors...)
		if childSexp != nil {
			tableElements = append(tableElements, childSexp)
		}
	}

	tableErr := SyntaxError{Pos: tokens[firstIndex].pos}
	if len(tableElements)%2 != 0 {
		tableErr.Message = "table literal expects an even number of elements (key-value pairs)"
		errors = append(errors, tableErr)
		return tableErr, errors
	}

	for i := 0; i < len(tableElements); i += 2 {
		key, ok := tableElements[i].(Keyword)
		if !ok {
			tableErr.Message = "table key must be a :keyword"
			errors = append(errors, tableErr)
			return tableErr, errors
		}

		table[string(key)] = tableElements[i+1]
	}

	return table, errors
}

func parseBool(t string) Boolean {
	if t == "#f" || t == "#F" {
		return false
	}
	return true
}

func parseNumber(t string) Number {
	if strings.ContainsAny(t, "ij") {
		c, _ := strconv.ParseComplex(t, 128)
		return Complex(c)
	}

	if strings.ContainsAny(t, ".eE") {
		f, _ := strconv.ParseFloat(t, 64)
		return Float(f)
	}

	i, _ := strconv.Atoi(t)
	return Int(i)
}
