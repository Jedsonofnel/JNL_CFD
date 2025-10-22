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

	eval_errors // sentinel value

	ErrRecursionLimitReached
	ErrFiberCancelled
	ErrArity
	ErrDivisionByZero
	ErrIndexOutOfRange
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
	accumulator := strings.Builder{}
	accumulator.WriteString(e.Error())
	accumulator.WriteString("\n")
	accumulator.WriteString(prettyFormatError(e.block, e.token, e.Message))
	accumulator.WriteString("\n")
	return accumulator.String()
}

func (e SyntaxError) ToJSON() string {
	return formatErrJSON("SyntaxError", e.Message, &e.token.pos)
}

// such that it implements Sexp
func (e SyntaxError) Type() string   { return "error" }
func (e SyntaxError) String() string { return "ERROR: " + e.Message }
func (e SyntaxError) evaluatable()   {}

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
}

func (e ExpansionError) Error() string {
	return "Expansion error: " + e.Message
}

func (e ExpansionError) PrettyError() string {
	return "Expansion error: " + e.Message
}

func (f *fiber) newErrMacroArity(macro string, wanted, got int) ExpansionError {
	return ExpansionError{
		Code:    ErrMacroArity,
		Message: macro + " wants " + strconv.Itoa(wanted) + " arguments but got " + strconv.Itoa(got),
		stack:   f.copyStack(),
	}
}

func (f *fiber) newErrMacroArityMinimum(macro string, minimum, got int) ExpansionError {
	return ExpansionError{
		Code:    ErrMacroArity,
		Message: macro + " wants minimum " + strconv.Itoa(minimum) + " arguments but got " + strconv.Itoa(got),
		stack:   f.copyStack(),
	}
}

func (f *fiber) newErrMacroArgType(macro, wanted string, pos int) ExpansionError {
	return ExpansionError{
		Code:    ErrMacroArgType,
		Message: macro + " wants type " + wanted + " at argument position " + strconv.Itoa(pos),
		stack:   f.copyStack(),
	}
}

// ELABORATION ERROR

type ElaborationError struct {
	Message string
}

func (e ElaborationError) Error() string {
	return "Elaboration error: " + e.Message
}

func (e ElaborationError) PrettyError() string {
	return "Elaboration error: " + e.Message
}

// Created by the evaluator
type EvalError struct {
	Code    ErrorCode
	Message string
	stack   []frame
}

func (e EvalError) Error() string       { return e.Message }
func (e EvalError) PrettyError() string { return e.Message }

func (f *fiber) newErrRecursionLimitReached() EvalError {
	return EvalError{
		Code:    ErrRecursionLimitReached,
		Message: "recursion limit reached: " + strconv.Itoa(f.maxDepth),
		stack:   f.copyStack(),
	}
}

func (f *fiber) newErrArityMin(name string, wanted, got int) EvalError {
	return EvalError{
		Code:    ErrArity,
		Message: name + " expects at least " + strconv.Itoa(wanted) + " arguments, got " + strconv.Itoa(got),
		stack:   f.copyStack(),
	}
}

func (f *fiber) newErrArityMax(name string, wanted, got int) EvalError {
	return EvalError{
		Code:    ErrArity,
		Message: name + " expects at most " + strconv.Itoa(wanted) + " arguments, got " + strconv.Itoa(got),
		stack:   f.copyStack(),
	}
}

// Created by the evaluator
type RuntimeError struct {
	Message string
}

func (e RuntimeError) Error() string {
	return "Runtime error: " + e.Message
}

func (e RuntimeError) PrettyError() string {
	return "Runtime error: " + e.Message
}

func ArgCountErr(funcName string, expected, got int) RuntimeError {
	return RuntimeError{
		Message: funcName + " expects " + strconv.Itoa(expected) +
			" arguments, got " + strconv.Itoa(got),
	}
}

func MinArgCountErr(funcName string, min, got int) RuntimeError {
	return RuntimeError{
		Message: funcName + " expects at least " + strconv.Itoa(min) +
			" arguments, got " + strconv.Itoa(got),
	}
}

func TypeErr(funcName, expected, got string) RuntimeError {
	return RuntimeError{
		Message: funcName + " expects " + expected + ", got " + got,
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

// Returns the line of source code containing the given token position
func getLineContaining(block *Block, token token) string {
	src := block.Src
	relativeOffset := token.pos.Offset - src.Start.Offset
	if relativeOffset < 0 || relativeOffset > len(src.Text) {
		return ""
	}

	lineStart := relativeOffset
	for lineStart > 0 && src.Text[lineStart-1] != '\n' {
		lineStart--
	}
	lineEnd := relativeOffset
	for lineEnd < len(src.Text) && src.Text[lineEnd] != '\n' {
		lineEnd++
	}
	return src.Text[lineStart:lineEnd]
}

func prettyFormatError(block *Block, token token, msg string) string {
	accumulator := strings.Builder{}

	// line numbers
	lineNum := strconv.Itoa(token.pos.Line)
	accumulator.WriteString(strings.Repeat(" ", len(lineNum)+1) + "|\n")
	accumulator.WriteString(lineNum + " | ")
	accumulator.WriteString(getLineContaining(block, token) + "\n")
	accumulator.WriteString(strings.Repeat(" ", len(lineNum)+1) + "| ")

	src := block.Src

	// caret underline
	relativeOffset := token.pos.Offset - src.Start.Offset
	lineStart := relativeOffset
	for lineStart > 0 && src.Text[lineStart-1] != '\n' {
		lineStart--
	}
	caretStart := relativeOffset - lineStart
	if caretStart-1 > len(msg) {
		accumulator.WriteString(strings.Repeat(" ", caretStart-len(msg)-1))
		accumulator.WriteString(msg + " ")
	} else {
		accumulator.WriteString(strings.Repeat(" ", caretStart))
	}

	caretLength := len(token.val)
	if token.typ == tokenDoubleNewline {
		caretLength = 1
	}
	accumulator.WriteString(strings.Repeat("^", caretLength) + " ")

	if caretStart-1 <= len(msg) {
		accumulator.WriteString(msg)
	}

	return accumulator.String()
}
