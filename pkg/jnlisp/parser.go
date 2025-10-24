package jnlisp

import (
	"strconv"
	"strings"
)

// parser acts on these
type Source struct {
	Text     string
	Filename string
	Start    Pos
	End      Pos
}

// parser produces these
type Block struct {
	// Lexer/parser metadata
	BlockType BlockType
	Src       Source
	tokens    []token

	AST Sexp

	// Syntax errors found in this block
	Errors []Error
}

func (b Block) Type() string { return "jnlisp-block" }
func (b Block) String() string {
	accumulator := strings.Builder{}

	if b.BlockType == CodeBlock {
		accumulator.WriteString(b.AST.String() + "\n")
	}
	accumulator.WriteString(b.SyntaxErrors())
	return accumulator.String()
}

func (b Block) SyntaxErrors() string {
	accumulator := strings.Builder{}
	for _, err := range b.Errors {
		if _, ok := err.(missingDelim); ok { // don't display these
			continue
		}
		accumulator.WriteString(err.PrettyError())
	}
	return accumulator.String()
}

// implements Indexed
type Document []Block

func (doc Document) Type() string { return "jnlisp-document" }
func (doc Document) String() string {
	accumulator := strings.Builder{}
	for i := range doc {
		block := doc[i]
		accumulator.WriteString(block.String())
	}
	return accumulator.String()
}

func (doc Document) First() Sexp {
	if len(doc) == 0 {
		return Nil{}
	}
	return doc[0]
}

func (doc Document) Rest() Seq {
	if doc.Empty() {
		return Nil{}
	}
	newDoc := make(Document, len(doc)-1)
	copy(newDoc, doc[1:])
	return newDoc
}

func (doc Document) Empty() bool {
	return len(doc) == 0
}

func (doc Document) Nth(i int) (Sexp, bool) {
	numBlocks := len(doc)
	if i > 0 && i < numBlocks {
		return doc[i], true
	}

	return nil, false
}

func (doc Document) Length() int {
	return len(doc)
}

func findSyntaxErrors(sexp Sexp) []Error {
	var errs []Error

	switch sexp := sexp.(type) {
	case List:
		for _, child := range sexp.Elements {
			errs = append(errs, findSyntaxErrors(child)...)
		}
	case Vector:
		for _, child := range sexp.Elements {
			errs = append(errs, findSyntaxErrors(child)...)
		}
	case Map:
		for _, child := range sexp.Elements {
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

func parse(src Source) Document {
	lexer := lex(src)
	parser := &parser{
		lex: lexer,
		src: src.Text,
	}
	var blocks []Block

Loop:
	for {
		b := Block{}
		parser.block = &b
		tok := parser.next()

		b.Src.Start = tok.pos
		b.Src.Filename = src.Filename

		switch tok.typ {
		case tokenEOF:
			break Loop
		case tokenDoubleNewline:
			continue // skip for now
		case tokenProse:
			b.BlockType = ProseBlock
		case tokenOpenJParen, tokenOpenParen:
			b.BlockType = CodeBlock
			b.AST = parseList(parser)
			b.Errors = findSyntaxErrors(b.AST)
		default:
			panic("unexpected token type in parse: " + tok.String())
		}

		endPos := parser.current.pos
		endPos.Offset += len(parser.current.val) // add the width of the token
		b.Src.End = endPos
		b.Src.Text = src.Text[b.Src.Start.Offset:endPos.Offset]

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
func (m missingDelim) String() string      { return "#<missing-delim:" + string(m) + ">" }
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
	list := List{start: p.current.pos}
	var elems []Sexp
	var tok token

Loop:
	for {
		tok = p.next()
		switch tok.typ {
		case tokenCloseParen:
			break Loop
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			elems = append(elems, p.newErrMissingDelimiter(tok, ")"))
			break Loop
		case tokenEOF:
			p.backup()
			elems = append(elems, missingDelim(")"))
			break Loop
		case tokenMapkey:
			p.backup()
			elems = append(elems, parseMap(p, tokenCloseParen))
		default:
			p.backup()
			elems = append(elems, parseCode(p))
		}
	}

	list.Elements = elems
	list.end = tok.pos
	return list
}

func parseVector(p *parser) Vector {
	vector := Vector{start: p.current.pos}
	var elems []Sexp
	var tok token

Loop:
	for {
		tok = p.next()
		switch tok.typ {
		case tokenCloseBracket:
			break Loop
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			elems = append(elems, p.newErrMissingDelimiter(tok, "]"))
			break Loop
		case tokenEOF:
			p.backup()
			elems = append(elems, missingDelim("]"))
			break Loop
		case tokenMapkey:
			p.backup()
			elems = append(elems, parseMap(p, tokenCloseBracket))
		default:
			p.backup()
			elems = append(elems, parseCode(p))
		}
	}

	vector.Elements = elems
	vector.end = tok.pos
	return vector
}

// parse map with an optional delimeter
// (brace for map literal, paren/bracket for inline map with mapkey: value syntax)
func parseMap(p *parser, delim tokenType) Sexp {
	mapp := Map{
		Elements: make(map[string]Sexp),
		start:    p.current.pos,
	}
	list := List{start: p.current.pos}

	var elems []Sexp
	var tok token

Loop:
	for {
		tok = p.next()
		switch tok.typ {
		case delim:
			if delim != tokenCloseBrace {
				p.backup() // if not a map literal don't consume
			}
			break Loop
		case tokenDoubleNewline, tokenOpenJParen:
			p.backup()
			elems = append(elems, p.newErrMissingDelimiter(tok, "}"))
			break Loop
		case tokenEOF:
			p.backup()
			elems = append(elems, missingDelim("}"))
			break Loop
		case tokenKeyword, tokenMapkey:
			key := strings.Trim(tok.val, ":")
			if _, exists := mapp.Elements[key]; exists {
				elems = append(elems, p.newErrDuplicateMapKeys(tok))
			}
			switch p.peek().typ {
			case tokenCloseBrace:
				p.next() // consume the delimiter
				elems = append(elems, p.newErrExpectedKeyValue(tok, key))
				break Loop
			case tokenMapkey:
				elems = append(elems, p.newErrExpectedKeyValue(tok, key))
			case tokenDoubleNewline, tokenEOF, delim:
				elems = append(elems, p.newErrExpectedKeyValue(tok, key))
				break Loop
			}
			value := parseCode(p)
			if len(key) == 0 {
				elems = append(elems, p.newErrMalformedKeyword(tok))
				elems = append(elems, value)
			} else {
				elems = append(elems, Keyword(key))
				elems = append(elems, value)
				mapp.append(key, value)
			}
		default:
			// don't add duplicate expected keywords
			if err, existing := elems[len(elems)-1].(SyntaxError); !existing || err.Code != ErrExpectedKeyword {
				elems = append(elems, p.newErrExpectedKeyword(tok))
			}
		}
	}

	// if there's an error - return the list
	for i := range elems {
		if _, ok := elems[i].(Error); ok {
			list.Elements = elems
			list.end = tok.pos
			return list
		}
	}

	mapp.end = tok.pos
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
		t = strings.Replace(t, "j", "i", 1)
		c, err := strconv.ParseComplex(t, 128)
		if err != nil {
			panic("Error parsing complex number: " + err.Error())
		}
		return Complex(c)
	}

	if strings.ContainsAny(t, ".eE") {
		f, _ := strconv.ParseFloat(t, 64)
		return Float(f)
	}

	i, _ := strconv.Atoi(t)
	return Int(i)
}
