package jnlisp

import (
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"
)

// MAIN INTERACTION

// looks for 'j(' glyph to start top-level s-exp
func tokenizeSrc(input string) []token {
	lex := lex(input, lexScanSrcExpr)
	tokens := make([]token, 0)

	for {
		next := lex.nextItem()
		if next.typ == tokenEOF || next.typ == tokenError {
			break
		}
		tokens = append(tokens, next)
	}

	return tokens
}

// just looks for '(' to start top-level s-exp
func tokenizeREPL(input string) []token {
	l := lex(input, lexScanExpr)
	tokens := make([]token, 0)

	for {
		next := l.nextItem()
		if next.typ == tokenEOF || next.typ == tokenError {
			tokens = append(tokens, next)
			break
		}
		tokens = append(tokens, next)
	}

	return tokens
}

func validateTokens(tokens []token) (int, error) {
	count := 0
	for _, token := range tokens {
		if token.typ == tokenMissingParen {
			count++
		}

		if token.typ == tokenError {
			return 0, fmt.Errorf("%s", token.val)
		}
	}

	return count, nil
}

// LEXER

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
	tokenError tokenType = iota
	tokenEOF
	tokenMissingParen

	tokenOpenParen
	tokenCloseParen
	tokenNumber
	tokenString
	tokenBool
	tokenSymbol
	tokenKeyword
)

// some strings we're looking for
const (
	openList    = "("
	openSrcList = "j("
	closeList   = ")"
	eof         = -1
)

func (i token) String() string {
	switch i.typ {
	case tokenEOF:
		return fmt.Sprintf("EOF@%s", i.pos)
	case tokenError:
		return fmt.Sprintf("ERROR@%s: %s", i.pos, i.val)
	case tokenMissingParen:
		return fmt.Sprintf("MISSING_PAREN@%s", i.pos)
	case tokenNumber:
		return fmt.Sprintf("NUMBER:%q@%s", i.val, i.pos)
	case tokenString:
		return fmt.Sprintf("STRING:%q@%s", i.val, i.pos)
	case tokenBool:
		return fmt.Sprintf("BOOL:%q@%s", i.val, i.pos)
	case tokenSymbol:
		return fmt.Sprintf("SYMBOL:%q@%s", i.val, i.pos)
	case tokenKeyword:
		return fmt.Sprintf("KEYWORD:%q@%s", i.val, i.pos)
	}

	if len(i.val) > 10 {
		return fmt.Sprintf("%.10q...@%s", i.val, i.pos)
	}
	return fmt.Sprintf("%q@%s", i.val, i.pos)
}

type lexer struct {
	input     string
	state     stateFn
	rootState stateFn
	tokens    chan token
	stack     []stateFn // for nested lists

	// Position tracking
	pos       int // current position in input (bytes)
	start     int // start of current token
	width     int // width of last rune read
	line      int // current line (1-based)
	lineStart int // byte offset where current line started
}

func lex(input string, state stateFn) *lexer {
	l := &lexer{
		input:     input,
		state:     state,               // the starting state
		rootState: state,               // keeping track of the starting state
		tokens:    make(chan token, 2), // two tokens sufficient - ring buffer
		line:      1,                   // start at line 1
		lineStart: 0,                   // line starts at beginning
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

// returns an error token to terminate the scan
func (l *lexer) errorf(format string, args ...any) stateFn {
	l.tokens <- token{
		typ: tokenError,
		val: fmt.Sprintf(format, args...),
		pos: l.currentPos(),
	}
	return nil
}

// to go "down" a layer
func (l *lexer) push(returnState stateFn) {
	l.stack = append(l.stack, returnState)
}

// to go "up" a layer
func (l *lexer) pop() stateFn {
	if len(l.stack) == 0 {
		return l.rootState
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
		if strings.HasPrefix(l.input[l.pos:], openList) {
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

// Start source file (ie looking for openParenMd)
func lexScanSrcExpr(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
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

func lexOpenList(l *lexer) stateFn {
	l.pos += len(openList)
	l.emit(tokenOpenParen)
	return lexInsideList
}

func lexOpenSrcList(l *lexer) stateFn {
	l.pos += len(openSrcList)
	l.emit(tokenOpenParen)
	return lexInsideList
}

func lexInsideList(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openList) {
			l.push(lexInsideList) // return here when it closes
			return lexOpenList
		}
		if strings.HasPrefix(l.input[l.pos:], closeList) {
			return lexCloseList
		}
		switch r := l.next(); {
		case r == eof:
			l.emit(tokenMissingParen)
			return l.pop()
		case isSpace(r):
			l.ignore()
		default:
			l.backup()
			return dispatchToken(l, r)
		}
	}
}

func dispatchToken(l *lexer, r rune) stateFn {
	switch r {
	case ';':
		return lexComment
	case '"':
		return lexString
	case '#':
		return lexLiteral
	case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
		return lexNumber
	case '+', '-':
		if next := l.peek(); isDigit(next) {
			return lexNumber
		}
		return lexSymbol
	case ':':
		return lexKeyword
	default:
		if isSymbolChar(r) {
			return lexSymbol
		}

		return l.errorf("unexpected character: %c", r)
	}
}

func lexCloseList(l *lexer) stateFn {
	l.pos += len(closeList)
	l.emit(tokenCloseParen)
	return l.pop()
}

func lexLiteral(l *lexer) stateFn {
	l.next() // consume '#'

	switch r := l.next(); r {
	case 't', 'T', 'f', 'F':
		l.emit(tokenBool)
		return lexInsideList
	}
	return nil
}

func lexString(l *lexer) stateFn {
	l.next()   // consume "
	l.ignore() // ignore it

	for {
		switch r := l.next(); r {
		case eof:
			return l.errorf("unterminated string")
		case '"':
			l.backup()
			l.emit(tokenString)
			l.next()
			l.ignore()
			return lexInsideList
		case '\\':
			if l.next() == eof {
				return l.errorf("unterminated string escape")
			}
			// the next() consumes the escaped char and will be inside the string
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
			return l.errorf("invalid complex number format")
		}
	} else {
		l.accept("ij")
	}

	l.emit(tokenNumber)
	return lexInsideList
}

func lexSymbol(l *lexer) stateFn {
	l.acceptRun(symbolChars())
	l.emit(tokenSymbol)

	return lexInsideList
}

func lexComment(l *lexer) stateFn {
	for {
		r := l.next()
		if r == '\n' || r == eof {
			break
		}
	}

	l.ignore() // we don't do anything with comments
	return lexInsideList
}

func lexKeyword(l *lexer) stateFn {
	l.next() // consume ':'
	l.ignore()

	l.acceptRun(symbolChars())
	l.emit(tokenKeyword)

	return lexInsideList
}

// helpers

func isSpace(r rune) bool {
	return unicode.IsSpace(r)
}

func isSymbolChar(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsDigit(r) ||
		strings.ContainsRune("-+*/%?!<>=_&|^~", r)
}

func symbolChars() string {
	return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-+*/%?!<>=_&|^~"
}

func isDigit(r rune) bool {
	return unicode.IsDigit(r)
}
