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
		accumulator.WriteString("\n\r")
	}
	return accumulator.String()
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
			// b.FindSyntaxErrors()
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
		return String(tok.val)
	case tokenSymbol:
		return parseSymbol(tok.val)
	case tokenKeyword:
		return Keyword(tok.val)
	case tokenUnenclosedString,
		tokenMalformedNumber:
		return newSyntaxErrorFromToken(tok)
	default:
		return newUnexpectedTokenError(tok)
	}
}

func parseList(p *parser) List {
	var list List

Loop:
	for {
		tok := p.next()
		switch tok.typ {
		case tokenCloseParen:
			break Loop
		case tokenDoubleNewline, tokenEOF, tokenOpenJParen:
			p.backup()
			list = append(list, SyntaxError{Message: "missing close list"})
			return list
		default:
			p.backup()
			list = append(list, parseCode(p))
		}
	}

	return list
}

func parseVector(p *parser) Vector {
	vector := Vector{}

	for {
		tok := p.next()
		switch tok.typ {
		case tokenCloseBracket:
			return vector
		case tokenDoubleNewline, tokenEOF, tokenOpenJParen:
			p.backup()
			vector = append(vector, SyntaxError{Message: "missing close vector"})
			return vector
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
			return table
		case tokenDoubleNewline, tokenEOF, tokenOpenJParen:
			p.backup()
			return SyntaxError{Message: "missing close table brace"}
		case tokenKeyword:
			peek := p.peek().typ
			if peek == delim || peek == tokenDoubleNewline || peek == tokenEOF {
				return SyntaxError{Message: "table expects an even number of elements (key-value pairs)"}
			}
			table[tok.val] = parseCode(p)
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
