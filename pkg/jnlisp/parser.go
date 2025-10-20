package jnlisp

import (
	"strconv"
	"strings"
)

// parser produces these
type Block struct {
	// Lexer/parser metadata
	Type  BlockType
	Start Pos
	End   Pos

	src    string
	tokens []token

	AST Sexp

	// Syntax errors found in this block
	Errors []Error
}

type Document []Block

func (doc Document) String() string {
	accumulator := strings.Builder{}
	for i := range doc {
		accumulator.WriteString(doc[i].AST.String())
		accumulator.WriteString("\n")
	}
	return accumulator.String()
}

func findSyntaxErrors(sexp Sexp) []Error {
	var errs []Error

	switch sexp := sexp.(type) {
	case List:
		for _, child := range sexp {
			errs = append(errs, findSyntaxErrors(child)...)
		}
	case Vector:
		for _, child := range sexp {
			errs = append(errs, findSyntaxErrors(child)...)
		}
	case Table:
		for _, child := range sexp {
			errs = append(errs, findSyntaxErrors(child)...)
		}
	case SyntaxError:
		errs = append(errs, sexp)
	case missingDelim:
		errs = append(errs, sexp)
	}

	return errs
}

type BlockType int

const (
	CodeBlock BlockType = iota
	ProseBlock
)

type parser struct {
	lex *lexer
	src string

	current token
	backed  bool
}

func (p *parser) next() token {
	if p.backed {
		p.backed = false
		return p.current // return backed up value
	}
	p.current = p.lex.nextToken()
	return p.current
}

func (p *parser) backup() {
	if p.backed {
		panic("parser: cannot backup twice")
	}
	p.backed = true
}

func (p *parser) peek() token {
	tok := p.next()
	p.backup()
	return tok
}

func parse(src string) Document {
	lexer := lex(src)
	parser := &parser{
		lex: lexer,
		src: src,
	}
	var blocks []Block

Loop:
	for {
		tok := parser.next()
		b := Block{Start: tok.pos}

		switch tok.typ {
		case tokenEOF:
			break Loop
		case tokenDoubleNewline:
			continue // skip for now
		case tokenProse:
			b.Type = ProseBlock
		case tokenOpenJParen, tokenOpenParen:
			b.Type = CodeBlock
			b.AST = parseList(parser)
			b.Errors = findSyntaxErrors(b.AST)
		default:
			panic("unexpected token type in parse: " + tok.String())
		}

		b.End = parser.current.pos
		b.src = src[b.Start.Offset:b.End.Offset]

		blocks = append(blocks, b)
	}

	return blocks
}

// Creates a tree structure from tokens with no semantic analysis
func parseCode(p *parser) Sexp {
	tok := p.next()
	switch tok.typ {
	case tokenOpenParen:
		return parseList(p)
	case tokenOpenBracket:
		return parseVector(p)
	case tokenOpenBrace:
		return parseTable(p, tokenCloseBrace)
	case tokenCloseParen, tokenCloseBracket, tokenCloseBrace:
		return newUnexpectedClosingTokenError(tok)
	case tokenNumber:
		return parseNumber(tok.val)
	case tokenString:
		return String(strings.Trim(tok.val, "\""))
	case tokenSymbol:
		return parseSymbol(tok.val)
	case tokenKeyword:
		return Keyword(strings.Trim(tok.val, ":"))
	case tokenUnenclosedString,
		tokenMalformedNumber:
		return newSyntaxErrorFromToken(tok)
	default:
		return newUnexpectedTokenError(tok)
	}
}

type missingDelim string

func (m missingDelim) Error() string  { return "Missing delimeter: " + string(m) }
func (m missingDelim) String() string { return "MISSING DELIM: " }
func (m missingDelim) Type() string   { return "error" }
func (m missingDelim) matching() string {
	switch m {
	case ")":
		return "("
	case "}":
		return "{"
	case "]":
		return "["
	default:
		return string(m)
	}
}

func parseList(p *parser) List {
	var list List

	for {
		tok := p.next()
		switch tok.typ {
		case tokenCloseParen:
			return list
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			list = append(list, SyntaxError{Message: "missing close list"})
			return list
		case tokenEOF:
			p.backup()
			list = append(list, missingDelim(")"))
			return list
		case tokenTablekey:
			p.backup()
			list = append(list, parseTable(p, tokenCloseParen))
		default:
			p.backup()
			list = append(list, parseCode(p))
		}
	}
}

func parseVector(p *parser) Vector {
	vector := Vector{}

	for {
		tok := p.next()
		switch tok.typ {
		case tokenCloseBracket:
			return vector
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			vector = append(vector, SyntaxError{Message: "missing close vector"})
			return vector
		case tokenEOF:
			p.backup()
			vector = append(vector, missingDelim("]"))
			return vector
		case tokenTablekey:
			p.backup()
			vector = append(vector, parseTable(p, tokenCloseBracket))
		default:
			p.backup()
			vector = append(vector, parseCode(p))
		}
	}
}

// parse table with an optional delimeter
// (brace for table literal, paren for inline table)
func parseTable(p *parser, delim tokenType) Sexp {
	table := make(Table)

	for {
		tok := p.next()
		switch tok.typ {
		case delim:
			if delim != tokenCloseBrace {
				p.backup() // if not a table literal don't consume
			}
			return table
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			return SyntaxError{Message: "missing close table brace"}
		case tokenEOF:
			p.backup()
			return missingDelim("}")
		case tokenKeyword, tokenTablekey:
			peek := p.peek().typ
			if peek == delim || peek == tokenDoubleNewline || peek == tokenEOF {
				return SyntaxError{Message: "table expects an even number of elements (key-value pairs)"}
			}
			key := strings.Trim(tok.val, ":")
			table[key] = parseCode(p)
		default:
			return SyntaxError{Message: "bad table formatting"}
		}
	}
}

func parseSymbol(t string) Sexp {
	switch t {
	case "true":
		return Boolean(true)
	case "false":
		return Boolean(false)
	case "nil":
		return nil
	default:
		return Symbol(t)
	}
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
