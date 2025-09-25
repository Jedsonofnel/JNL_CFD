package jnlisp

import (
	"fmt"
	"strconv"
	"strings"
)

// basic types
type symbol string

func (s symbol) String() string {
	return fmt.Sprintf("SYMBOL:%q", string(s))
}

// type string string

type list []exp

type exp any

func newSymbol(s string) symbol { return symbol(s) }

// doesn't expect any markdown block stuff in between - only s-exps
func parseREPL(tokens []token) ([]exp, error) {
	var expressions []exp
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

func parseExpression(tokens []token, idx *int) (exp, error) {
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

	case tokenSymbol:
		return newSymbol(token.val), nil

	case tokenNumber:
		return parseNumber(token.val), nil
	default:
		return nil, fmt.Errorf("unexpected token: %v", token)
	}
}

func parseNumber(s string) exp {
	if strings.ContainsAny(s, "ij") {
		c, _ := strconv.ParseComplex(s, 128)
		return c
	}

	if strings.ContainsAny(s, ".eE") {
		f, _ := strconv.ParseFloat(s, 32)
		return float32(f)
	}

	i, _ := strconv.Atoi(s)
	return i
}
