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

func (b Block) String() string {
	accumulator := strings.Builder{}

	if b.Type == CodeBlock {
		accumulator.WriteString(b.AST.String() + "\n")
	}

	for _, err := range b.Errors {
		accumulator.WriteString(err.PrettyError() + "\n")
	}

	return accumulator.String()
}

type Document []Block

func (doc Document) String() string {
	accumulator := strings.Builder{}
	for i := range doc {
		block := doc[i]
		accumulator.WriteString(block.String())
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
	case Map:
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

	block *Block // current block being parsed
}

func (p *parser) next() token {
	if p.backed {
		p.backed = false
		return p.current // return backed up value
	}
	p.current = p.lex.nextToken()
	p.block.tokens = append(p.block.tokens, p.current) // auto-save
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
		b := Block{}
		parser.block = &b
		tok := parser.next()

		b.Start = tok.pos

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
		return parseMap(p, tokenCloseBrace)
	case tokenCloseParen, tokenCloseBracket, tokenCloseBrace:
		return p.newErrUnexpectedDelimiter(tok)
	case tokenNumber:
		return parseNumber(tok.val)
	case tokenString:
		return String(strings.Trim(tok.val, "\""))
	case tokenSymbol:
		return parseSymbol(tok.val)
	case tokenKeyword:
		return Keyword(strings.Trim(tok.val, ":"))
	case tokenUnenclosedString:
		return p.newErrUnenclosedString(tok)
	case tokenMalformedNumber:
		return p.newErrMalformedNumber(tok)
	default:
		return p.newErrUnexpectedToken(tok)
	}
}

type missingDelim string

func (m missingDelim) Error() string       { return "Missing delimeter: " + string(m) }
func (m missingDelim) PrettyError() string { return "Missing delimeter: " + string(m) }
func (m missingDelim) String() string      { return "MISSING DELIM: " }
func (m missingDelim) Type() string        { return "error" }
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
			list = append(list, p.newErrMissingDelimiter(tok, ")"))
			return list
		case tokenEOF:
			p.backup()
			list = append(list, missingDelim(")"))
			return list
		case tokenMapkey:
			p.backup()
			list = append(list, parseMap(p, tokenCloseParen))
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
			vector = append(vector, p.newErrMissingDelimiter(tok, "]"))
			return vector
		case tokenEOF:
			p.backup()
			vector = append(vector, missingDelim("]"))
			return vector
		case tokenMapkey:
			p.backup()
			vector = append(vector, parseMap(p, tokenCloseBracket))
		default:
			p.backup()
			vector = append(vector, parseCode(p))
		}
	}
}

// parse map with an optional delimeter
// (brace for map literal, paren/bracket for inline map with mapkey: value syntax)
func parseMap(p *parser, delim tokenType) Sexp {
	mapp := make(Map)
	var elements List

Loop:
	for {
		tok := p.next()
		switch tok.typ {
		case delim:
			if delim != tokenCloseBrace {
				p.backup() // if not a map literal don't consume
			}
			break Loop
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			elements = append(elements, p.newErrMissingDelimiter(tok, "}"))
		case tokenEOF:
			p.backup()
			return append(elements, missingDelim("}"))
		case tokenKeyword, tokenMapkey:
			key := strings.Trim(tok.val, ":")
			if _, exists := mapp[key]; exists {
				elements = append(elements, p.newErrDuplicateMapKeys(tok))
			}
			switch p.peek().typ {
			case tokenCloseBrace:
				p.next() // consume the delimiter
				return append(elements, p.newErrExpectedKeyValue(tok, key))
			case tokenMapkey:
				elements = append(elements, p.newErrExpectedKeyValue(tok, key))
			case tokenDoubleNewline, tokenEOF, delim:
				return append(elements, p.newErrExpectedKeyValue(tok, key))
			}
			value := parseCode(p)
			mapp[key] = value
			elements = append(elements, Keyword(key))
			elements = append(elements, value)
		default:
			elements = append(elements, p.newErrExpectedKeyword(tok))
		}
	}

	// if there's an error - return the list
	for i := range elements {
		if _, ok := elements[i].(Error); ok {
			return elements
		}
	}

	return mapp
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
