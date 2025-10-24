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
	lineErrs := getErrorLinesFromStack(e.stack, e.block)
	accumulator := strings.Builder{}
	accumulator.WriteString(e.Error())
	accumulator.WriteString("\n")
	accumulator.WriteString(lineErrs.displayWithMessage(e.Message))
	accumulator.WriteString("\n")
	return accumulator.String()
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
	lines := getErrorLinesFromStack(e.stack, e.block)
	accumulator := strings.Builder{}
	accumulator.WriteString(e.Error())
	accumulator.WriteString("\n")
	accumulator.WriteString(lines.displayWithMessage(e.Message))
	accumulator.WriteString("\n")
	return accumulator.String()
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
	lines := getErrorLinesFromStack(e.stack, e.block)
	accumulator := strings.Builder{}
	accumulator.WriteString(e.Error())
	accumulator.WriteString("\n")
	accumulator.WriteString(lines.displayWithMessage(e.Message))
	accumulator.WriteString("\n")
	return accumulator.String()
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

func (f *fiber) newErrPosArgType(name, wanted, got string, pos int) EvalError {
	return EvalError{
		Code:    ErrArgType,
		Message: "'" + name + "' expects " + wanted + ", as arg at position " + strconv.Itoa(pos) + ", got " + got,
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

type errLine struct {
	line     string // the full string of the line without newlines
	lineNum  int    // the line number of each line
	carStart int    // the string index at which the caret underline should start
	carEnd   int    // the string index at which the caret underline should end
}

type errLines []errLine

// creates a string with the errLines underlined and a message somewhere
func (e errLines) displayWithMessage(msg string) string {
	if len(e) == 0 {
		return ""
	}

	accumulator := strings.Builder{}
	last := e[len(e)-1] // always print the last one
	lastNum := strconv.Itoa(last.lineNum)

	// TODO make this display multilines reasonably well
	firstNonWhitespace := 0

WhitespaceSearch:
	for i := range len(last.line) {
		switch last.line[i] {
		case ' ', '\t', '\v', '\f', '\r':
			continue WhitespaceSearch
		default:
			firstNonWhitespace = 0
			break WhitespaceSearch
		}
	}

	accumulator.WriteString(strings.Repeat(" ", len(lastNum)) + " |\n")
	accumulator.WriteString(lastNum + " | ")
	accumulator.WriteString(last.line + "\n")
	accumulator.WriteString(strings.Repeat(" ", len(lastNum)) + " | ")

	carStart := firstNonWhitespace
	if last.carStart > 0 && last.carEnd > 0 {
		carStart = last.carStart
	}

	if carStart >= len(msg)+1 {
		accumulator.WriteString(strings.Repeat(" ", carStart-len(msg)-1) + " ")
		accumulator.WriteString(msg)
	} else {
		accumulator.WriteString(strings.Repeat(" ", carStart))
	}

	accumulator.WriteString(strings.Repeat("^", last.carEnd-carStart))

	if carStart < len(msg)+1 {
		accumulator.WriteString(" " + msg)
	}

	accumulator.WriteString("\n")
	accumulator.WriteString(strings.Repeat(" ", len(lastNum)) + " | ")
	return accumulator.String()
}

// from stack data find the lines with errors
func getErrorLinesFromStack(stack []frame, block *Block) errLines {
	var idx int
	var start, end Pos

SexpDescent:
	for i := len(stack) - 1; i >= 0; i-- {
		idx = stack[i].idx // update
		switch sexp := stack[i].sexp.(type) {
		case List:
			if sexp.start.Line != 0 && sexp.end.Line != 0 {
				start, end = sexp.start, sexp.end
				break SexpDescent
			}
		case Vector:
			if sexp.start.Line != 0 && sexp.end.Line != 0 {
				start, end = sexp.start, sexp.end
				break SexpDescent
			}
		case Map:
			if sexp.start.Line != 0 && sexp.end.Line != 0 {
				start, end = sexp.start, sexp.end
				break SexpDescent
			}
		}
	}

	src := block.Src
	relativeOffset := start.Offset - src.Start.Offset
	if relativeOffset < 0 || relativeOffset > len(src.Text) {
		println("RELATIVE OFFSET BAD")
		return []errLine{}
	}

	// get first line
	lineStart := relativeOffset
	for lineStart > 0 && src.Text[lineStart-1] != '\n' {
		lineStart--
	}

	// use the block tokens to figure out position of indexed child
	var childStartTokenIdx int
	for i := range block.tokens {
		if block.tokens[i].pos.Offset == start.Offset {
			childStartTokenIdx = i + 1
			break
		}
	}

	// chunk through tokens until the nth child start/end has been found
	depth := 0
	traversed := -1
	childEndTokenIdx := childStartTokenIdx
	for i := range block.tokens[childStartTokenIdx+1:] {
		switch block.tokens[i].typ {
		case tokenOpenParen, tokenOpenBracket, tokenOpenBrace:
			depth++
		case tokenCloseParen, tokenCloseBracket, tokenCloseBrace:
			depth--
		}

		switch depth {
		case 0:
			traversed++
		case -1:
			panic("error traversing through children in line error fetching")
		}

		// ie have we consumed the zero-indexed nth child yet
		if traversed >= idx {
			childEndTokenIdx = i
			break
		}
	}

	// error child start offset and end offset
	childStart := block.tokens[childStartTokenIdx].pos.Offset - src.Start.Offset
	childEnd := block.tokens[childEndTokenIdx].pos.Offset + // offset to start of token
		len(block.tokens[childEndTokenIdx].val) - // + length of token
		src.Start.Offset

	var lines errLines
	for i := relativeOffset; i < len(src.Text); i++ {
		if src.Text[i] == '\n' || i == len(src.Text)-1 {
			newLine := errLine{
				line:     src.Text[lineStart : i+1],
				lineNum:  start.Line + len(lines),
				carStart: childStart - lineStart,
				carEnd:   childEnd - lineStart,
			}

			lineStart = i + 1 // reset lineStart skipping the newline
			lines = append(lines, newLine)

			if i >= end.Offset { // ie don't keep looping if at the end of sexp offset
				break
			}
		}
	}

	return lines
}

func getSyntaxErrorLine(token token, block *Block) errLines {
	var lines errLines
	src := block.Src

	relativeOffset := token.pos.Offset - src.Start.Offset
	if relativeOffset < 0 || relativeOffset > len(src.Text) {
		return lines
	}

	lineStart := relativeOffset
	for lineStart > 0 && src.Text[lineStart-1] != '\n' {
		lineStart--
	}
	lineEnd := relativeOffset
	for lineEnd < len(src.Text) && src.Text[lineEnd] != '\n' {
		lineEnd++
	}

	return append(lines, errLine{
		line:     src.Text[lineStart:lineEnd],
		lineNum:  token.pos.Line,
		carStart: relativeOffset - lineStart,
		carEnd:   relativeOffset - lineStart + len(token.val),
	})
}
