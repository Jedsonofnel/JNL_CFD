package jnlisp

import (
	"strconv"
	"strings"
)

type Error interface {
	error
	PrettyError() string
}

type ErrorCode int

func (e ErrorCode) String() string {
	a := strconv.Itoa(int(e))
	for len(a) <= 3 { // make the digit 3 chars wide
		a = "0" + a
	}
	return "E" + a
}

// Error codes for all types of errors
const (
	syntax_errors ErrorCode = iota // sentinel value

	ErrMissingDelimiter
	ErrUnexpectedDelimiter
	ErrUnexpectedToken
	ErrMalformedNumber
	ErrMalformedKeyword // when a keyword is a single colon
	ErrUnenclosedString
	ErrDuplicateMapKeys
	ErrExpectedKeyValue // when a keyword isn't followed by a value
	ErrExpectedKeyword  // when it's not a keyword in a map

	expansion_errors // sentinel value

	ErrMacroArity
	ErrMacroArgType
	ErrMacroInvalidForm

	elaboration_errors // sentinel value

	ErrElaborationSyntax
	ErrElaborationArity // errors with arity literal

	eval_errors // sentinel value

	ErrRecursionLimitReached
	ErrFiberCancelled
	ErrArity
	ErrArgType
	ErrUnexpectedKwarg
	ErrIndexOutOfRange
	ErrSymbolNotBound
	ErrNonCallableCalled
	ErrDivisionByZero
	ErrEmptyList
)

// created during filesystem lookups
type FileSystemError struct {
	path    string
	op      string // "read", "walk", "stat" etc
	err     error
	Message string
}

func newFSError(path, op string, err error) FileSystemError {
	message := "error during " + op + " of " + path + ": " + err.Error()
	return FileSystemError{path, op, err, message}
}

func (e FileSystemError) Error() string {
	return "File system error: " + e.Message
}

func (e FileSystemError) PrettyError() string {
	return "File system error: " + e.Message
}

// Created by the parser - implements Sexp
type SyntaxError struct {
	Code    ErrorCode
	Message string
	token   token
	block   *Block // debating this
}

func (e SyntaxError) Error() string {
	pos := e.block.Src.Filename + ":" + e.token.pos.String()
	return e.Code.String() + " at " + pos + ": " + e.Message
}

func (e SyntaxError) PrettyError() string {
	lines := getSyntaxErrorLine(e.token, e.block)
	accumulator := strings.Builder{}
	accumulator.WriteString(e.Error())
	accumulator.WriteString("\n")
	accumulator.WriteString(lines.displayWithMessage(e.Message))
	accumulator.WriteString("\n")
	return accumulator.String()
}

func (e SyntaxError) ToJSON() string {
	return formatErrJSON("SyntaxError", e.Message, &e.token.pos)
}

// such that it implements Sexp
func (e SyntaxError) Type() string   { return "error" }
func (e SyntaxError) String() string { return "#<error:" + e.Message + ">" }

func (p *parser) newErrMissingDelimiter(t token, delim string) SyntaxError {
	return SyntaxError{
		Code:    ErrMissingDelimiter,
		Message: "missing delimiter: '" + delim + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrUnexpectedDelimiter(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrUnexpectedDelimiter,
		Message: "unexpected delimeter: '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrUnexpectedToken(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrUnexpectedToken,
		Message: "unexpected token: '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrMalformedNumber(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrMalformedNumber,
		Message: "malformed number: '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrMalformedKeyword(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrMalformedKeyword,
		Message: "keyword must have a body, got '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrUnenclosedString(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrUnenclosedString,
		Message: "unenclosed string: '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrDuplicateMapKeys(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrDuplicateMapKeys,
		Message: "duplicate map key: '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrExpectedKeyValue(t token, key string) SyntaxError {
	return SyntaxError{
		Code:    ErrExpectedKeyValue,
		Message: "expected value for key: '" + key + "'",
		token:   t,
		block:   p.block,
	}
}

func (p *parser) newErrExpectedKeyword(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrExpectedKeyword,
		Message: "expected keyword in map, got: '" + t.val + "'",
		token:   t,
		block:   p.block,
	}
}

// Created during expansion
type ExpansionError struct {
	Code    ErrorCode
	Message string
	stack   []frame
	block   *Block
}

func (e ExpansionError) Error() string {
	pos := e.block.Src.Filename
	return e.Code.String() + " at " + pos + ": " + e.Message
}

func (e ExpansionError) PrettyError() string {
	snippet := getErrorSnippet(e.stack, e.block)
	b := strings.Builder{}
	b.WriteString(e.Error())
	b.WriteString("\n")
	b.WriteString(snippet.displayWithMessage(e.Message))
	b.WriteString("\n")
	b.WriteString(displayStack(e.stack))
	return b.String()
}

func (f *fiber) newErrMacroArity(macro string, wanted, got int) ExpansionError {
	return ExpansionError{
		Code:    ErrMacroArity,
		Message: macro + " wants " + strconv.Itoa(wanted) + " arguments but got " + strconv.Itoa(got),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrMacroArityMinimum(macro string, minimum, got int) ExpansionError {
	return ExpansionError{
		Code:    ErrMacroArity,
		Message: macro + " wants minimum " + strconv.Itoa(minimum) + " arguments but got " + strconv.Itoa(got),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrMacroArgType(macro, wanted string, pos int) ExpansionError {
	return ExpansionError{
		Code:    ErrMacroArgType,
		Message: macro + " wants type " + wanted + " at argument position " + strconv.Itoa(pos),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

// ELABORATION ERROR

type ElaborationError struct {
	Code    ErrorCode
	Message string
	stack   []frame
	block   *Block
}

func (e ElaborationError) Error() string {
	pos := e.block.Src.Filename
	return e.Code.String() + " at " + pos + ": " + e.Message
}

func (e ElaborationError) PrettyError() string {
	snippet := getErrorSnippet(e.stack, e.block)
	b := strings.Builder{}
	b.WriteString(e.Error())
	b.WriteString("\n")
	b.WriteString(snippet.displayWithMessage(e.Message))
	b.WriteString("\n")
	b.WriteString(displayStack(e.stack))
	return b.String()
}

func (f *fiber) newErrElaborationSyntax(msg string) ElaborationError {
	return ElaborationError{
		Code:    ErrElaborationSyntax,
		Message: msg,
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrElaborationAritySyntax(msg string) ElaborationError {
	return ElaborationError{
		Code:    ErrElaborationArity,
		Message: msg,
		stack:   f.copyStack(),
		block:   f.block,
	}
}

// Created by the evaluator
type EvalError struct {
	Code    ErrorCode
	Message string
	stack   []frame
	block   *Block
}

func (e EvalError) Error() string {
	pos := e.block.Src.Filename
	return e.Code.String() + " at " + pos + ": " + e.Message
}

func (e EvalError) PrettyError() string {
	snippet := getErrorSnippet(e.stack, e.block)
	b := strings.Builder{}
	b.WriteString(e.Error())
	b.WriteString("\n")
	b.WriteString(snippet.displayWithMessage(e.Message))
	b.WriteString("\n")
	b.WriteString(displayStack(e.stack))
	return b.String()
}

func (f *fiber) newErrRecursionLimitReached() EvalError {
	return EvalError{
		Code:    ErrRecursionLimitReached,
		Message: "recursion limit reached: " + strconv.Itoa(f.maxDepth),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrArity(name string, arity Arity, got []Sexp) EvalError {
	vecGot := Vector{Elements: got}
	return EvalError{
		Code:    ErrArity,
		Message: "'" + name + "' expects " + arity.String() + ", got " + vecGot.String(),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrMultiArity(name string, arities MultiArity, got []Sexp) EvalError {
	vecGot := Vector{Elements: got}
	return EvalError{
		Code:    ErrArity,
		Message: "'" + name + "' expects " + arities.String() + ", got " + vecGot.String(),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrPosArgType(name, wanted, got string, pos int) EvalError {
	return EvalError{
		Code:    ErrArgType,
		Message: "'" + name + "' expects " + wanted + " as arg at position " + strconv.Itoa(pos) + ", got " + got,
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrVariadicArgType(name, wanted, got string, pos int) EvalError {
	return EvalError{
		Code:    ErrArgType,
		Message: "'" + name + "' expects " + wanted + ", as variadic arg type, got " + got + " at position " + strconv.Itoa(pos),
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrKwargType(name, key, wanted, got string) EvalError {
	return EvalError{
		Code:    ErrArgType,
		Message: "'" + name + "' expects " + wanted + ", as type for key '" + key + "', got " + got,
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrUnexpectedKwarg(name, kwarg string) EvalError {
	return EvalError{
		Code:    ErrUnexpectedKwarg,
		Message: "'" + name + "' received unexpected kwarg '" + kwarg + "'",
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrIndexOutOfRange(index, length int) EvalError {
	return EvalError{
		Code:    ErrIndexOutOfRange,
		Message: "index requested '" + strconv.Itoa(index) + "' is out of range [0:" + strconv.Itoa(length) + "]",
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrSymbolNotBound(name string) EvalError {
	return EvalError{
		Code:    ErrSymbolNotBound,
		Message: "could not find symbol '" + name + "' in current environment",
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrNonCallableCalled(called string) EvalError {
	return EvalError{
		Code:    ErrNonCallableCalled,
		Message: "cannot call non-callable type '" + called + "'",
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrDivisionByZero() EvalError {
	return EvalError{
		Code:    ErrDivisionByZero,
		Message: "cannot divide by zero",
		stack:   f.copyStack(),
		block:   f.block,
	}
}

func (f *fiber) newErrEmptyList() EvalError {
	return EvalError{
		Code:    ErrEmptyList,
		Message: "cannot evaluate an empty list",
		stack:   f.copyStack(),
		block:   f.block,
	}
}

// HELPER FUNCTIONS

func formatErrJSON(typ, message string, pos *Pos) string {
	json := `{"type": ` + escapeJSON(typ) +
		`, "message": ` + escapeJSON(message)

	if pos != nil {
		json += `, "position": ` + pos.ToJSON()
	}

	return json + "}"
}

func escapeJSON(s string) string {
	result := ""
	for _, c := range s {
		switch c {
		case '"':
			result += `\"`
		case '\\':
			result += `\\`
		case '\n':
			result += `\n`
		case '\r':
			result += `\r`
		case '\t':
			result += `\t`
		default:
			result += string(c)
		}
	}
	return result
}

type errorSnippet struct {
	text       string
	lineNum    int
	caretStart int
	caretEnd   int
}

func (e errorSnippet) displayWithMessage(msg string) string {
	var b strings.Builder

	lineNumStr := strconv.Itoa(e.lineNum)
	padding := strings.Repeat(" ", len(lineNumStr))

	// header
	b.WriteString(padding + " |\n")

	// source line
	b.WriteString(lineNumStr + " | " + e.text + "\n")

	// caret line
	b.WriteString(padding + " | ")

	if e.caretStart >= len(msg)+1 {
		b.WriteString(strings.Repeat(" ", e.caretStart-len(msg)-1) + " ")
		b.WriteString(msg)
	} else {
		b.WriteString(strings.Repeat(" ", e.caretStart))
	}

	b.WriteString(strings.Repeat("^", e.caretEnd-e.caretStart))

	if e.caretStart < len(msg)+1 {
		b.WriteString(" " + msg)
	}

	b.WriteString("\n")
	b.WriteString(padding + " |")
	return b.String()
}

// from stack data find the lines with errors
func getErrorSnippet(stack []frame, block *Block) errorSnippet {
	var idx int
	var start, end Pos

	for i := len(stack) - 1; i >= 0; i-- {
		switch sexp := stack[i].sexp.(type) {
		case List:
			if sexp.start.Line != 0 && sexp.end.Line != 0 {
				start, end = sexp.start, sexp.end
				goto Found
			}
		case Vector:
			if sexp.start.Line != 0 && sexp.end.Line != 0 {
				start, end = sexp.start, sexp.end
				goto Found
			}
		case Map:
			if sexp.start.Line != 0 && sexp.end.Line != 0 {
				start, end = sexp.start, sexp.end
				goto Found
			}
		}
		idx = stack[i].idx // update idx of child
	}

Found:
	src := block.Src
	parentStart := start.Offset - src.Start.Offset
	parentEnd := end.Offset - src.Start.Offset

	if parentStart < 0 || parentStart > len(src.Text) {
		panic("Error parent position is out of bounds of registered block, see jnlisp/errors.go:getErrSnippet()")
	}

	// walk back to start of the line
	lineStart := parentStart
	for lineStart > 0 && src.Text[lineStart-1] != '\n' {
		lineStart--
	}

	// walk to the last newline containing the error
	lineEnd := parentStart
	for lineEnd < len(src.Text) && !(lineEnd >= parentEnd && src.Text[lineEnd] == '\n') {
		lineEnd++
	}

	isMultiLine := start.Line != end.Line

	// Extract text and replace newlines with visible glyph
	displayText := src.Text[lineStart:lineEnd]
	if isMultiLine {
		displayText = strings.ReplaceAll(displayText, "\n", "↵   ")
	}

	// use the block tokens to figure out position of parent list/vec/map
	var parentStartTokenIdx int
	for i := range block.tokens {
		if block.tokens[i].pos.Offset == start.Offset {
			parentStartTokenIdx = i + 1 // increment by one to get first child
			break
		}
	}

	childStart, childEnd := findChildBounds(block, parentStartTokenIdx, idx)

	caretStart := childStart - src.Start.Offset - lineStart
	caretEnd := childEnd - src.Start.Offset - lineStart

	if isMultiLine {
		beforeStart := src.Text[lineStart : lineStart+caretStart]
		newlinesBeforeStart := strings.Count(beforeStart, "\n")
		caretStart -= newlinesBeforeStart * (1 - 4) // \n removed, enter char (4 wide) added (net 4)

		beforeEnd := src.Text[lineStart : lineStart+caretEnd]
		newlinesBeforeEnd := strings.Count(beforeEnd, "\n")
		caretEnd -= newlinesBeforeEnd * (1 - 4)
	}

	// double check
	caretStart = max(0, min(caretStart, len(displayText)))
	caretEnd = max(caretStart+1, min(caretEnd, len(displayText)))

	return errorSnippet{
		text:       displayText,
		lineNum:    start.Line,
		caretStart: caretStart,
		caretEnd:   caretEnd,
	}
}

// chunk through tokens until the nth child start/end has been found
func findChildBounds(block *Block, parentStart, childIdx int) (int, int) {
	depth := 0
	numToTraverse := childIdx
	var childStartTokenIdx, childEndTokenIdx = -1, -1 // -1 for now

	for i := parentStart; i < len(block.tokens); i++ {
		if numToTraverse == 0 && depth == 0 { // ie got to start of child
			childStartTokenIdx = i
		}

		switch block.tokens[i].typ {
		case tokenOpenParen, tokenOpenBracket, tokenOpenBrace:
			depth++
		case tokenCloseParen, tokenCloseBracket, tokenCloseBrace:
			depth--
		}

		switch depth {
		case 0:
			numToTraverse--
		case -1:
			panic("error traversing through children in line error fetching")
		}

		// ie we have consumed the idxth child
		if depth == 0 && childStartTokenIdx != -1 {
			childEndTokenIdx = i
			break
		}
	}

	// error child start offset and end offset
	childStart := block.tokens[childStartTokenIdx].pos.Offset -
		block.Src.Start.Offset
	childEnd := block.tokens[childEndTokenIdx].pos.Offset + // offset to start of token
		len(block.tokens[childEndTokenIdx].val) - // + length of token
		block.Src.Start.Offset

	return childStart, childEnd
}

func getSyntaxErrorLine(token token, block *Block) errorSnippet {
	src := block.Src

	relativeOffset := token.pos.Offset - src.Start.Offset
	if relativeOffset < 0 || relativeOffset > len(src.Text) {
		panic("relative offset calculated poorly, see getSyntaxErrorLine in errors.go")
	}

	lineStart := relativeOffset
	for lineStart > 0 && src.Text[lineStart-1] != '\n' {
		lineStart--
	}
	lineEnd := relativeOffset
	for lineEnd < len(src.Text) && src.Text[lineEnd] != '\n' {
		lineEnd++
	}

	return errorSnippet{
		text:       src.Text[lineStart:lineEnd],
		lineNum:    token.pos.Line,
		caretStart: relativeOffset - lineStart,
		caretEnd:   relativeOffset - lineStart + len(token.val),
	}
}
