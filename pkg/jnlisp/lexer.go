package jnlisp

import (
	"strconv"
	"strings"
	"unicode/utf8"
)

// CORE TYPES

type token struct {
	typ tokenType // type, such as tokenNumber
	val string    // value such as "23.2"
	pos Pos       // starting position of the token (first character)
}

type Pos struct {
	Line   int // 1-based line number
	Column int // 1-based column number
	Offset int // 0-based byte offset
}

func (p Pos) String() string {
	return strconv.Itoa(p.Line) + ":" + strconv.Itoa(p.Column)
}

func (p Pos) ToJSON() string {
	return `{"line": ` + strconv.Itoa(p.Line) +
		`, "column": ` + strconv.Itoa(p.Column) +
		`, "offset": ` + strconv.Itoa(p.Offset) + `}`
}

type tokenType int

const (
	// key delims
	tokenEOF tokenType = iota
	tokenDoubleNewline
	tokenOpenJParen

	tokenOpenParen
	tokenCloseParen
	tokenOpenBracket
	tokenCloseBracket
	tokenOpenBrace
	tokenCloseBrace

	tokenNumber
	tokenString
	tokenSymbol
	tokenKeyword
	tokenTablekey

	tokenUnenclosedString
	tokenMalformedNumber

	// Markdown block (prose) tokens
	tokenProse
)

var tokenStrings = []string{
	"tokenEOF",
	"tokenDoubleNewline",
	"tokenOpenJParen",

	"tokenOpenParen",
	"tokenCloseParen",
	"tokenOpenBracket",
	"tokenCloseBracket",
	"tokenOpenBrace",
	"tokenCloseBrace",

	"tokenNumber",
	"tokenString",
	"tokenSymbol",
	"tokenKeyword",
	"tokenTablekey",

	"tokenUnenclosedString",
	"tokenMalformedNumber",

	"tokenProse",
}

func (tt tokenType) String() string {
	return tokenStrings[tt]
}

// glyphs we're looking for
const (
	eof = -1
)

func (t token) String() string {
	return t.typ.String() + "\n\r"
}

type lexer struct {
	input  string
	state  lexFn
	tokens chan token
	stack  []lexFn // for nested lists

	// Position tracking
	pos       int // current position in input (bytes)
	start     int // start of current token
	width     int // width of last rune read
	line      int // current line (1-based)
	lineStart int // byte offset where current line started

	// Capture position at token start
	startLine int // current token's starting line
	startCol  int // current token's starting column
}

func lex(input string) *lexer {
	l := &lexer{
		input:  input,
		state:  lexStart,            // the starting state
		tokens: make(chan token, 2), // two tokens sufficient - ring buffer
		stack:  []lexFn{},

		line:      1, // start at line 1
		lineStart: 0, // line starts at beginning

		startLine: 1,
		startCol:  1,
	}
	return l
}

// returns the next token from the input.
// A bit of cleverness using concurrency thanks to Rob Pike's wonderful
// "lexical scanning in go" talk on youtube
func (l *lexer) nextToken() token {
	for {
		select {
		case token := <-l.tokens:
			return token
		default:
			l.state = l.state(l)
		}
	}
}

// HELPER METHODS ON LEXER

// passes an token block back to the client
// decorated with currentPos() data
func (l *lexer) emit(t tokenType) {
	l.tokens <- token{
		typ: t,
		val: l.input[l.start:l.pos],
		pos: Pos{
			Line:   l.startLine,
			Column: l.startCol,
			Offset: l.start,
		},
	}

	// reset start data
	l.start = l.pos
	l.startLine = l.line
	l.startCol = l.start - l.lineStart + 1
}

// consume next rune with line tracking
func (l *lexer) next() (r rune) {
	if l.pos >= len(l.input) {
		l.width = 0
		return eof
	}

	r, l.width = utf8.DecodeRuneInString(l.input[l.pos:])

	// increment newlines
	if r == '\n' {
		l.line++
		l.lineStart = l.pos + l.width // next line starts after this newline
	}

	l.pos += l.width
	return r
}

func (l *lexer) ignore() {
	l.start = l.pos
	l.startLine = l.line
	l.startCol = l.start - l.lineStart + 1
}

func (l *lexer) backup() {
	l.pos -= l.width

	if l.width > 0 && l.pos < len(l.input) {
		r, _ := utf8.DecodeRuneInString(l.input[l.pos:])
		if r == '\n' {
			l.line--
			// Find the start of the previous line
			l.lineStart = 0
			for i := l.pos - 1; i >= 0; i-- {
				if l.input[i] == '\n' {
					l.lineStart = i + 1
					break
				}
			}
		}
	}
}

func (l *lexer) peek() int32 {
	rune := l.next()
	l.backup()
	return rune
}

// accept consumes the next rune
// if it's from the valid set
func (l *lexer) accept(valid string) bool {
	if strings.ContainsRune(valid, l.next()) {
		return true
	}
	l.backup()
	return false
}

// accept consumes a run of runes from the valid set
func (l *lexer) acceptRun(valid string) {
	for strings.ContainsRune(valid, l.next()) {
	}
	l.backup()
}

// to go "down" a layer
func (l *lexer) push(returnState lexFn) {
	l.stack = append(l.stack, returnState)
}

// to go "up" a layer
func (l *lexer) pop() lexFn {
	if len(l.stack) == 0 {
		panic("LEXER: tried to pop out of root state - asymmetry detected")
	}

	n := len(l.stack) - 1
	state := l.stack[n]
	l.stack = l.stack[:n]
	return state
}

// STATE FUNCTIONS

type lexFn func(l *lexer) lexFn

// Looks for open paren - if otherwise assume it's a document rather than REPL
func lexStart(l *lexer) lexFn {
	for {
		switch r := l.next(); r {
		case '(': // if open paren backup and start REPL
			l.backup()
			return lexREPL
		case ';': // ignore comments
			l.push(lexStart)
			return lexComment
		case ' ', '\n', '\t', '\r':
			l.ignore()
		case eof:
			l.emit(tokenEOF)
			return nil
		default:
			l.backup()
			return lexDocument
		}
	}
}

// Start normal code scanning (no literate stuff)
func lexREPL(l *lexer) lexFn {
Loop:
	for {
		if strings.HasPrefix(l.input[l.pos:], "(") {
			l.pos += len("(")
			l.emit(tokenOpenParen)
			l.push(lexREPL)
			return lexInsideList // Next state
		}

		r := l.next()
		switch {
		case r == eof:
			break Loop
		case r == '\n' && isDoubleNewline(l):
			l.acceptRun(" \t\r\n")
			l.emit(tokenDoubleNewline)
		default:
			l.ignore()
		}
	}
	// reached EOF
	l.emit(tokenEOF)
	return nil
}

// Start document (ie markdown + code blocks)
func lexDocument(l *lexer) lexFn {
Loop:
	for {
		if strings.HasPrefix(l.input[l.pos:], "j(") {
			// only emit prose if we've accumulated content
			if l.pos > l.start {
				l.emit(tokenProse)
			}

			l.pos += len("j(")
			l.emit(tokenOpenJParen)
			l.push(lexDocument) // return here after top level block
			return lexInsideList
		}

		r := l.next()
		switch {
		case r == eof:
			break Loop
		case r == '\n' && isDoubleNewline(l):
			l.acceptRun(" \t\r\n")
			l.emit(tokenDoubleNewline)
		}
	}

	if l.pos > l.start {
		l.emit(tokenProse)
	}
	l.emit(tokenEOF)
	return nil
}

func lexInsideList(l *lexer) lexFn {
	for {
		switch r := l.next(); r {
		case ' ', '\t', '\r': // if whitespace then ignore
			l.ignore()
		case ')':
			l.emit(tokenCloseParen)
			return l.pop()
		case ']':
			l.emit(tokenCloseBracket)
		case '}':
			l.emit(tokenCloseBrace)
		default:
			l.backup()
			return lexInsideCompound(l, lexInsideList)
		}
	}
}

func lexInsideVec(l *lexer) lexFn {
	for {
		switch r := l.next(); r {
		case ' ', '\t', '\r': // if whitespace then ignore
			l.ignore()
		case ')':
			l.emit(tokenCloseParen)
		case ']':
			l.emit(tokenCloseBracket)
			return l.pop()
		case '}':
			l.emit(tokenCloseBrace)
		default:
			l.backup()
			return lexInsideCompound(l, lexInsideVec)
		}
	}
}

func lexInsideTable(l *lexer) lexFn {
	for {
		switch r := l.next(); r {
		case ' ', '\t', '\r': // if whitespace then ignore
			l.ignore()
		case ')':
			l.emit(tokenCloseParen)
		case ']':
			l.emit(tokenCloseBracket)
		case '}':
			l.emit(tokenCloseBrace)
			return l.pop()
		default:
			l.backup()
			return lexInsideCompound(l, lexInsideTable)
		}
	}
}

func lexInsideCompound(l *lexer, returnState lexFn) lexFn {
	if strings.HasPrefix(l.input[l.pos:], "j(") {
		return l.pop()
	}

	l.push(returnState)

	switch r := l.next(); r {
	case '(':
		l.emit(tokenOpenParen)
		return lexInsideList
	case '[':
		l.emit(tokenOpenBracket)
		return lexInsideVec
	case '{':
		l.emit(tokenOpenBrace)
		return lexInsideTable
	case eof:
		l.pop()
		return l.pop()
	case '\n':
		if isDoubleNewline(l) {
			l.backup()
			l.pop()        // back to parent state
			return l.pop() // out of parent state
		}
		l.ignore()
		return l.pop()
	default:
		l.backup()
		return lexAtom
	}
}

func lexAtom(l *lexer) lexFn {
	r := l.next()

	switch {
	case r == '"':
		return lexString
	case r == '#':
		return lexComment
	case isDigit(r):
		return lexNumber
	case r == '+' || r == '-':
		if next := l.peek(); isDigit(next) {
			l.backup() // put the +/- back
			return lexNumber
		}
		l.backup() // put the +/- back
		return lexSymbol
	case r == ':':
		return lexKeyword
	default:
		return lexSymbol
	}
}

func lexString(l *lexer) lexFn {
	for {
		switch r := l.next(); r {
		case eof:
			l.emit(tokenUnenclosedString)
			return l.pop()
		case '\n': // string must be on one line
			l.backup() // go back to end of string
			l.emit(tokenUnenclosedString)
			return l.pop()
		case '"':
			l.emit(tokenString)
			return l.pop()
		case '\\':
			if l.next() == eof { // next consumes the escaped char
				l.backup()
				l.emit(tokenUnenclosedString)
				return l.pop()
			}
		}
	}
}

func lexNumber(l *lexer) lexFn {
	lexNumberPart := func() {
		// leading sign (optional)
		l.accept("+-")

		// Is it hex?
		digits := "0123456789"
		if l.accept("0") && l.accept("xX") {
			digits = "0123456789abcdefABCDEF"
			l.acceptRun(digits)
			return
		}

		l.acceptRun(digits)

		// floating point
		if l.accept(".") {
			l.acceptRun(digits)
		}

		// scientific notation
		if l.accept("eE") {
			l.accept("+-")
			l.acceptRun("0123456789")
		}
	}

	lexNumberPart()

	if l.accept("+-") {
		lexNumberPart()
		if !l.accept("ij") {
			// TODO: new type of token?
			l.emit(tokenMalformedNumber)
			return l.pop()
		}
	} else {
		l.accept("ij")
	}

	l.emit(tokenNumber)
	return l.pop()
}

func lexSymbol(l *lexer) lexFn {
	for {
		r := l.next()
		if !isSymbolChar(r) {
			l.backup() // put the delimeter back
			break
		}
	}

	if strings.HasSuffix(l.input[l.start:l.pos], ":") {
		l.emit(tokenTablekey)
	} else {
		l.emit(tokenSymbol)
	}

	return l.pop()
}

func lexComment(l *lexer) lexFn {
	for {
		r := l.next()
		if r == '\n' || r == eof {
			break
		}
	}

	l.ignore() // we don't do anything with comments
	return l.pop()
}

func lexKeyword(l *lexer) lexFn {
	for {
		r := l.next()
		if !isSymbolChar(r) {
			l.backup()
			break
		}
	}

	l.emit(tokenKeyword)
	return l.pop()
}

// helpers

const digitChars = "0123456789"
const specialChars = "()[]{}\"';# \t\n\r"

func isSymbolChar(r rune) bool {
	return r != eof && !strings.ContainsRune(specialChars, r)
}

func isDigit(r rune) bool {
	return strings.ContainsRune(digitChars, r)
}

func isDoubleNewline(l *lexer) bool {
	pos := l.pos // We're positioned right after first \n

	// Skip whitespace (but not newlines)
	for pos < len(l.input) {
		r, width := utf8.DecodeRuneInString(l.input[pos:])
		if strings.ContainsRune(" \t\r", r) {
			pos += width
			continue
		}

		if r == '\n' {
			return true // Found second newline!
		}

		// Hit non-whitespace, non-newline
		return false
	}

	return false // Hit EOF
}
