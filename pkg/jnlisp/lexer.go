package jnlisp

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

// MAIN EXTERNAL INTERACTION

// looks for 'j(' glyph to start top-level s-exp
func tokenizeSrc(input string) []token {
	return tokenize(input, lexScanSrcExpr)
}

// just looks for '(' to start top-level s-exp
func tokenizeREPL(input string) []token {
	return tokenize(input, lexScanExpr)
}

func tokenize(input string, rootLexer stateFn) (tokens []token) {
	lex := lex(input, rootLexer)
	for {
		next := lex.nextItem()
		if next.typ == tokenEOF {
			break
		}
		tokens = append(tokens, next)
	}

	return tokens
}

// TODO: make this also return a list of syntax errors
func validateTokens(tokens []token) (missing []string) {
	for _, token := range tokens {
		switch token.typ {
		case tokenMissingCloseList:
			missing = append(missing, ")")
		case tokenMissingCloseVec:
			missing = append(missing, "]")
		}
	}

	return missing
}

// CORE TYPES

type token struct {
	typ tokenType // Type, such as tokenNumber
	val string    // Value such as "23.2"
	pos Pos
}

type Pos struct {
	Line   int `json:"line"`   // 1-based line number
	Column int `json:"column"` // 1-based column number
	Offset int `json:"offset"` // 0-based byte offset
}

func (p Pos) String() string {
	return fmt.Sprintf("%d:%d", p.Line, p.Column)
}

type tokenType int

const (
	tokenEOF tokenType = iota

	tokenMissingCloseList
	tokenMissingCloseVec
	tokenMissingCloseString
	tokenMalformedNumber
	tokenInvalidLiteral

	tokenOpenList
	tokenCloseList
	tokenOpenVec
	tokenCloseVec
	tokenNumber
	tokenString
	tokenBool
	tokenSymbol
	tokenKeyword
)

var tokenStrings = []string{
	"tokenEOF",

	"tokenMissingCloseList",
	"tokenMissingCloseVec",
	"tokenMissingCloseString",
	"tokenMalformedNumber",
	"tokenInvalidLiteral",

	"tokenOpenList",
	"tokenCloseList",
	"tokenOpenVec",
	"tokenCloseVec",
	"tokenNumber",
	"tokenString",
	"tokenBool",
	"tokenSymbol",
	"tokenKeyword",
}

func (tt tokenType) String() string {
	return tokenStrings[tt]
}

// glyphs we're looking for
const (
	openSrcList = "j("
	eof         = -1
)

func (i token) String() string {
	switch i.typ {
	case tokenEOF:
		return fmt.Sprintf("EOF@%s\n", i.pos)
	case tokenMissingCloseList:
		return fmt.Sprintf("MISSING_PAREN@%s\n", i.pos)
	case tokenMissingCloseVec:
		return fmt.Sprintf("MISSING_PAREN@%s\n", i.pos)
	case tokenNumber:
		return fmt.Sprintf("NUMBER:%q@%s ", i.val, i.pos)
	case tokenString:
		return fmt.Sprintf("STRING:%q@%s ", i.val, i.pos)
	case tokenBool:
		return fmt.Sprintf("BOOL:%q@%s ", i.val, i.pos)
	case tokenSymbol:
		return fmt.Sprintf("SYMBOL:%q@%s ", i.val, i.pos)
	case tokenKeyword:
		return fmt.Sprintf("KEYWORD:%q@%s ", i.val, i.pos)
	}

	if len(i.val) > 10 {
		return fmt.Sprintf("%.10q...@%s ", i.val, i.pos)
	}
	return fmt.Sprintf("%q@%s ", i.val, i.pos)
}

type lexer struct {
	input  string
	state  stateFn
	tokens chan token
	stack  []stateFn // for nested lists

	// Position tracking
	pos       int // current position in input (bytes)
	start     int // start of current token
	width     int // width of last rune read
	line      int // current line (1-based)
	lineStart int // byte offset where current line started
}

func lex(input string, rootState stateFn) *lexer {
	l := &lexer{
		input:  input,
		state:  rootState,           // the starting state
		tokens: make(chan token, 2), // two tokens sufficient - ring buffer
		stack:  []stateFn{},

		line:      1, // start at line 1
		lineStart: 0, // line starts at beginning
	}
	return l
}

// returns the next token from the input
// bit of cleverness using concurrency thanks to Rob Pike
func (l *lexer) nextItem() token {
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

// get current position
func (l *lexer) currentPos() Pos {
	return Pos{
		Line:   l.line,
		Column: l.start - l.lineStart + 1,
		Offset: l.start,
	}
}

// passes an token block back to the client
// decorated with currentPos() data
func (l *lexer) emit(t tokenType) {
	l.tokens <- token{
		typ: t,
		val: l.input[l.start:l.pos],
		pos: l.currentPos(),
	}
	l.start = l.pos
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
func (l *lexer) push(returnState stateFn) {
	l.stack = append(l.stack, returnState)
}

// to go "up" a layer
func (l *lexer) pop() stateFn {
	if len(l.stack) == 0 {
		panic("LEXER: tried to pop out of root state - asymmetry detected")
	}

	n := len(l.stack) - 1
	state := l.stack[n]
	l.stack = l.stack[:n]
	return state
}

// STATE FUNCTIONS

type stateFn func(l *lexer) stateFn

// Start normal code block (no literate stuff)
func lexScanExpr(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], "(") {
			l.push(lexScanExpr)
			return lexOpenList // Next state
		}
		if l.next() == eof { // advance input checking for EOF
			break
		}
		l.ignore()
	}
	// reached EOF
	l.emit(tokenEOF)
	return nil
}

// Start source file (ie looking for openParenSrc)
func lexScanSrcExpr(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			l.push(lexScanSrcExpr) // return here after top level block
			return lexOpenSrcList
		}
		if l.next() == eof {
			break
		}
		l.ignore()
	}

	l.emit(tokenEOF)
	return nil
}

func lexOpenSrcList(l *lexer) stateFn {
	l.pos += len(openSrcList)
	l.emit(tokenOpenList)
	return lexInsideList
}

func lexOpenList(l *lexer) stateFn {
	l.pos += len("(")
	l.emit(tokenOpenList)
	return lexInsideList
}

func lexCloseList(l *lexer) stateFn {
	l.pos += len(")")
	l.emit(tokenCloseList)
	return l.pop()
}

func lexInsideList(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			l.emit(tokenMissingCloseList)
			return l.pop()
		}

		switch r := l.next(); r {
		case '(':
			l.push(lexInsideList) // return here when finished
			return lexOpenList
		case '[':
			l.push(lexInsideList)
			return lexOpenVec
		case ')':
			return lexCloseList
		case ']':
			l.emit(tokenMissingCloseList)
			return l.pop()
		case '"':
			l.push(lexInsideList)
			return lexString
		case eof:
			l.emit(tokenMissingCloseList)
			return l.pop()
		case '\n':
			l.backup()
			l.push(lexInsideList)
			return lexNewline(l, tokenMissingCloseList)
		case ' ', '\t', '\r':
			l.ignore()
		default:
			l.push(lexInsideList)
			l.backup()
			return dispatchToken(l, r)
		}
	}
}

func lexOpenVec(l *lexer) stateFn {
	l.pos += len("[")
	l.emit(tokenOpenVec)
	return lexInsideVec
}

func lexCloseVec(l *lexer) stateFn {
	l.pos += len("]")
	l.emit(tokenCloseVec)
	return l.pop()
}

func lexInsideVec(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			l.emit(tokenMissingCloseVec)
			return l.pop()
		}

		switch r := l.next(); r {
		case '[':
			l.push(lexInsideVec) // return here when finished
			return lexOpenVec
		case '(':
			l.push(lexInsideVec)
			return lexOpenList
		case ']':
			return lexCloseVec
		case ')':
			l.emit(tokenMissingCloseVec)
			return l.pop()
		case eof:
			l.emit(tokenMissingCloseVec)
			return l.pop()
		case '\n':
			l.backup()
			l.push(lexInsideVec)
			return lexNewline(l, tokenMissingCloseVec)
		case ' ', '\t', '\r': // if whitespace then ignore
			l.ignore()
		default:
			l.push(lexInsideVec)
			l.backup()
			return dispatchToken(l, r)
		}
	}
}

// ensure the newline is just as single newline inside a list otherwise throw
// the specified missingToken and pop()
func lexNewline(l *lexer, missingToken tokenType) stateFn {
	r := l.peek() // ie we don't consume the double newline
	if r == '\n' {
		l.emit(missingToken)
		l.pop()        // back to parent
		return l.pop() // escape parent for cascade
	}

	l.ignore()
	return l.pop()
}

func dispatchToken(l *lexer, r rune) stateFn {
	switch {
	case r == '"':
		return lexString
	case r == ';':
		return lexComment
	case r == '#':
		return lexLiteral
	case isDigit(r):
		return lexNumber
	case r == '+' || r == '-':
		l.next() // consume the +/-
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

func lexLiteral(l *lexer) stateFn {
	l.next() // consume '#'

	switch r := l.next(); r {
	case 't', 'T', 'f', 'F':
		l.emit(tokenBool)
		return l.pop()
	default:
		// invalid literal - consume until delimiter
		for {
			r := l.next()
			if !isSymbolChar(r) {
				l.backup()
				break
			}
		}
		l.emit(tokenInvalidLiteral)
		return l.pop()
	}
}

func lexString(l *lexer) stateFn {
	l.next()   // consume "
	l.ignore() // ignore it

	for {
		switch r := l.next(); r {
		case eof:
			l.emit(tokenMissingCloseString)
			return l.pop()
		case '\n': // string must be on one line
			l.emit(tokenMissingCloseString)
			return l.pop()
		case '"':
			l.backup()
			l.emit(tokenString)
			l.next()
			l.ignore()
			return l.pop()
		case '\\':
			if l.next() == eof { // next consumes the escaped char
				l.emit(tokenMissingCloseString)
				return l.pop()
			}
		}
	}
}

func lexNumber(l *lexer) stateFn {
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

func lexSymbol(l *lexer) stateFn {
	for {
		r := l.next()
		if !isSymbolChar(r) {
			l.backup() // put the delimeter back
			break
		}
	}

	l.emit(tokenSymbol)
	return l.pop()
}

func lexComment(l *lexer) stateFn {
	for {
		r := l.next()
		if r == '\n' || r == eof {
			break
		}
	}

	l.ignore() // we don't do anything with comments
	return l.pop()
}

func lexKeyword(l *lexer) stateFn {
	l.next() // consume ':'
	l.ignore()

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
const specialChars = "()[]\"';#: \t\n\r"

func isSymbolChar(r rune) bool {
	return r != eof && !strings.ContainsRune(specialChars, r)
}

func isDigit(r rune) bool {
	return strings.ContainsRune(digitChars, r)
}
