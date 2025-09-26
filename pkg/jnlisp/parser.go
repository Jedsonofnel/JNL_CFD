package jnlisp

import (
	"fmt"
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

// doesn't expect any markdown block stuff in between - only s-exps
func parseREPL(tokens []token) ([]any, error) {
	var expressions []any
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenParen {
			exp, err := parseExpression(tokens, &idx)
			if err != nil {
				return nil, err
			}
			expressions = append(expressions, exp)
		} else {
			idx++ // skipping unexpected tokens
		}
	}

	return expressions, nil
}

type srcPosition struct {
	startPos Pos
	endPos   Pos
}

func parseSrc(tokens []token) ([]any, []srcPosition, error) {
	var expressions []any
	var srcPositions []srcPosition
	idx := 0

	for idx < len(tokens) && tokens[idx].typ != tokenEOF {
		if tokens[idx].typ == tokenOpenParen {
			pos := srcPosition{startPos: tokens[idx].pos}

			exp, err := parseExpression(tokens, &idx)
			if err != nil {
				return nil, nil, err
			}

			expressions = append(expressions, exp)
			pos.endPos = tokens[idx-1].pos
			srcPositions = append(srcPositions, pos)
		} else {
			idx++ // skipping anything between top level s-exps
		}
	}

	return expressions, srcPositions, nil
}

func parseExpression(tokens []token, idx *int) (any, error) {
	if *idx > len(tokens) {
		return nil, fmt.Errorf("unexpected EOF")
	}

	token := tokens[*idx]
	*idx++
	switch token.typ {
	case tokenOpenParen:
		var list list
		for *idx < len(tokens) && tokens[*idx].typ != tokenCloseParen {
			exp, err := parseExpression(tokens, idx)
			if err != nil {
				return nil, err
			}
			list = append(list, exp)
		}

		if *idx >= len(tokens) || tokens[*idx].typ != tokenCloseParen {
			return nil, fmt.Errorf("missing closing paren")
		}
		*idx++ // consume ")"
		return list, nil

	case tokenCloseParen:
		return nil, fmt.Errorf("unexpected ')'")

	case tokenOpenVec:
		var vec vector
		for *idx < len(tokens) && tokens[*idx].typ != tokenCloseVec {
			exp, err := parseExpression(tokens, idx)
			if err != nil {
				return nil, err
			}
			vec = append(vec, exp)
		}

		if *idx >= len(tokens) || tokens[*idx].typ != tokenCloseVec {
			return nil, fmt.Errorf("missing closing bracket")
		}
		*idx++ // consume "]"
		return vec, nil

	case tokenCloseVec:
		return nil, fmt.Errorf("unexpected ']'")

	case tokenString:
		return token.val, nil

	case tokenBool:
		return parseBool(token.val), nil

	case tokenNumber:
		return parseNumber(token.val), nil

	case tokenSymbol:
		return newSymbol(token.val), nil

	case tokenKeyword:
		return newKeyword(token.val), nil

	default:
		return nil, fmt.Errorf("unexpected token: %v", token)
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
