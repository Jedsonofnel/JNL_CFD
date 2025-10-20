package jnlisp

import (
	"strconv"
	"strings"
	"unicode/utf8"
)

// MAIN EXTERNAL INTERACTION

func tokenize(input string) (tokens []token) {
	lex := lex(input, lexStart)
	for {
		next := lex.nextItem()
		tokens = append(tokens, next)
		if next.typ == tokenEOF {
			break
		}
	}

	return tokens
}

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
	tokenEOF tokenType = iota

	tokenOpenList
	tokenCloseList
	tokenOpenVec
	tokenCloseVec
	tokenOpenTable
	tokenCloseTable

	tokenNumber
	tokenString
	tokenBool
	tokenSymbol
	tokenKeyword

	// Markdown block (prose) tokens
	tokenProse

	// sentinel marker - everything after is an error
	ERROR_TOKENS // not a real token

	// recoverable
	tokenMissingCloseList
	tokenMissingCloseVec
	tokenMissingCloseTable

	// unrecoverable errors
	tokenMissingCloseString
	tokenMalformedNumber
	tokenInvalidLiteral

	// unrecoverable
	tokenUnexpectedCloseList
	tokenUnexpectedCloseVec
	tokenUnexpectedCloseTable
)

var tokenStrings = []string{
	"tokenEOF",

	"tokenOpenList",
	"tokenCloseList",
	"tokenOpenVec",
	"tokenCloseVec",
	"tokenOpenTable",
	"tokenCloseTable",

	"tokenNumber",
	"tokenString",
	"tokenBool",
	"tokenSymbol",
	"tokenKeyword",

	"tokenProse",

	"ERROR_TOKENS_SENTINEL",

	"tokenMissingCloseList",
	"tokenMissingCloseVec",
	"tokenMissingCloseTable",

	"tokenMissingCloseString",
	"tokenMalformedNumber",
	"tokenInvalidLiteral",

	"tokenUnexpectedCloseList",
	"tokenUnexpectedCloseVec",
	"tokenUnexpectedCloseTable",
}

func (tt tokenType) String() string {
	return tokenStrings[tt]
}

func (tt tokenType) isError() bool {
	return tt > ERROR_TOKENS
}

func (tt tokenType) isMissingDelim() (bool, string) {
	switch tt {
	case tokenMissingCloseList:
		return true, "("
	case tokenMissingCloseVec:
		return true, "["
	case tokenMissingCloseTable:
		return true, "{"
	default:
		return false, ""
	}
}

// glyphs we're looking for
const (
	openSrcList = "j("
	eof         = -1
)

func (i token) String() string {
	switch i.typ {
	case tokenEOF:
		return "EOF(@" + i.pos.String() + ")\n"

	case tokenOpenList:
		return "\nOPENLIST( "
	case tokenCloseList:
		return " )CLOSELIST\n"
	case tokenOpenVec:
		return "\nOPENVEC[ "
	case tokenCloseVec:
		return " ]CLOSEVEC\n"
	case tokenOpenTable:
		return "\nOPENTABLE[ "
	case tokenCloseTable:
		return " ]CLOSETABLE\n"

	case tokenNumber:
		return "number(" + i.val + ", @" + i.pos.String() + ") "
	case tokenString:
		return "string(" + i.val + ", @" + i.pos.String() + ") "
	case tokenBool:
		return "bool(" + i.val + ", @" + i.pos.String() + ") "
	case tokenSymbol:
		return "symbol(" + i.val + ", @" + i.pos.String() + ") "
	case tokenKeyword:
		return "keyword(" + i.val + ", @" + i.pos.String() + ") "

	case tokenProse:
		return "--PROSE @" + i.pos.String() + "--\n"

	case ERROR_TOKENS:
		return "unexpected sentinel token\n"

	case tokenMissingCloseList:
		return "MISSING_PAREN(@" + i.pos.String() + ")\n"
	case tokenMissingCloseVec:
		return "MISSING_BRACKET(@" + i.pos.String() + ")\n"
	case tokenMissingCloseTable:
		return "MISSING_BRACE(@" + i.pos.String() + ")\n"
	case tokenMissingCloseString:
		return "MISSING_STRING_CLOSE(@" + i.pos.String() + ")\n"
	case tokenMalformedNumber:
		return "MALFORMED_NUMBER(@" + i.val + ", " + i.pos.String() + ")\n"

	case tokenUnexpectedCloseList:
		return "UNEXPECTED_PAREN(@" + i.pos.String() + ")\n"
	case tokenUnexpectedCloseVec:
		return "UNEXPECTED_BRACKET(@" + i.pos.String() + ")\n"
	case tokenUnexpectedCloseTable:
		return "UNEXPECTED_BRACE(@" + i.pos.String() + ")\n"

	default:
		return "UNKNOWN(" + i.val + ")\n"
	}
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

	// Capture position at token start
	startLine int // current token's starting line
	startCol  int // current token's starting column
}

func lex(input string, rootState stateFn) *lexer {
	l := &lexer{
		input:  input,
		state:  rootState,           // the starting state
		tokens: make(chan token, 2), // two tokens sufficient - ring buffer
		stack:  []stateFn{},

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

// Looks for open paren - if otherwise assume it's a document rather than REPL
func lexStart(l *lexer) stateFn {
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
func lexREPL(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], "(") {
			l.pos += len("(")
			l.emit(tokenOpenList)
			l.push(lexREPL)
			return lexInsideList // Next state
		}
		if l.next() == eof { // advance input checking for EOF
			break
		}
		l.ignore() // ignore if not an open paren
	}
	// reached EOF
	l.emit(tokenEOF)
	return nil
}

// Start document (ie markdown + code blocks)
func lexDocument(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			// only emit prose if we've accumulated content
			if l.pos > l.start {
				l.emit(tokenProse)
			}

			l.pos += len(openSrcList)
			l.emit(tokenOpenList)
			l.push(lexDocument) // return here after top level block
			return lexInsideList
		}

		if l.next() == eof {
			// only emit trailing prose if there's content
			if l.pos > l.start {
				l.emit(tokenProse)
			}
			break
		}
	}

	l.emit(tokenEOF)
	return nil
}

func lexInsideList(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			l.emit(tokenMissingCloseList)
			return l.pop()
		}

		switch r := l.next(); r {
		case '(':
			l.emit(tokenOpenList)
			l.push(lexInsideList) // return here when finished
			return lexInsideList
		case '[':
			l.emit(tokenOpenVec)
			l.push(lexInsideList)
			return lexInsideVec
		case '{':
			l.emit(tokenOpenTable)
			l.push(lexInsideList)
			return lexInsideTable
		case ')':
			l.emit(tokenCloseList)
			return l.pop()
		case ']':
			l.emit(tokenUnexpectedCloseVec)
		case '}':
			l.emit(tokenUnexpectedCloseTable)
		case eof:
			l.emit(tokenMissingCloseList)
			return l.pop()
		case '\n':
			l.push(lexInsideList)
			return lexNewline(l, tokenMissingCloseList)
		case ' ', '\t', '\r':
			l.ignore()
		default:
			l.push(lexInsideList)
			l.backup()
			return dispatchToken(l)
		}
	}
}

func lexInsideVec(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			l.emit(tokenMissingCloseVec)
			return l.pop()
		}

		switch r := l.next(); r {
		case '(':
			l.emit(tokenOpenList)
			l.push(lexInsideVec)
			return lexInsideList
		case '[':
			l.emit(tokenOpenVec)
			l.push(lexInsideVec) // return here when finished
			return lexInsideVec
		case '{':
			l.emit(tokenOpenTable)
			l.push(lexInsideVec)
			return lexInsideTable
		case ')':
			l.emit(tokenUnexpectedCloseList)
		case '}':
			l.emit(tokenUnexpectedCloseTable)
		case ']':
			l.emit(tokenCloseVec)
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
			return dispatchToken(l)
		}
	}
}

func lexInsideTable(l *lexer) stateFn {
	for {
		if strings.HasPrefix(l.input[l.pos:], openSrcList) {
			l.emit(tokenMissingCloseTable)
			return l.pop()
		}

		switch r := l.next(); r {
		case '(':
			l.emit(tokenOpenList)
			l.push(lexInsideTable) // return here when finished
			return lexInsideList
		case '[':
			l.emit(tokenOpenVec)
			l.push(lexInsideTable)
			return lexInsideVec
		case '{':
			l.emit(tokenOpenTable)
			l.push(lexInsideTable)
			return lexInsideTable
		case ')':
			l.emit(tokenUnexpectedCloseList)
		case ']':
			l.emit(tokenUnexpectedCloseVec)
		case '}':
			l.emit(tokenCloseTable)
			return l.pop()
		case eof:
			l.emit(tokenMissingCloseTable)
			return l.pop()
		case '\n':
			l.backup()
			l.push(lexInsideVec)
			return lexNewline(l, tokenMissingCloseTable)
		case ' ', '\t', '\r': // if whitespace then ignore
			l.ignore()
		default:
			l.push(lexInsideTable)
			l.backup()
			return dispatchToken(l)
		}
	}
}

// ensure the newline is just as single newline inside a list otherwise throw
// the specified missingToken and pop()
func lexNewline(l *lexer, missingToken tokenType) stateFn {
	r := l.peek() // ie we don't consume the double newline
	if r == '\n' {
		l.backup()
		l.emit(missingToken)
		l.pop()        // back to parent
		return l.pop() // escape parent for cascade
	}

	l.ignore()
	return l.pop()
}

func dispatchToken(l *lexer) stateFn {
	r := l.next()

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

// TODO remove this - no such thing - just have "nil", "true" and "false"
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
	l.ignore() // ignore the "

	for {
		switch r := l.next(); r {
		case eof:
			l.emit(tokenMissingCloseString)
			return l.pop()
		case '\n': // string must be on one line
			l.backup() // go back to end of string
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
	l.ignore() // consume the :

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
const specialChars = "()[]\"';# \t\n\r"

func isSymbolChar(r rune) bool {
	return r != eof && !strings.ContainsRune(specialChars, r)
}

func isDigit(r rune) bool {
	return strings.ContainsRune(digitChars, r)
}
