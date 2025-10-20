package jnlisp

import (
	"strconv"
)

type Error interface {
	error
}

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

// Created by the parser - implements Sexp
type SyntaxError struct {
	Pos     Pos
	Message string
}

func (e SyntaxError) Error() string {
	return "Syntax error at " + e.Pos.String() + ": " + e.Message
}

func (e SyntaxError) ToJSON() string {
	return formatErrJSON("SyntaxError", e.Message, &e.Pos)
}

func (e SyntaxError) Type() string   { return "error" }
func (e SyntaxError) String() string { return "ERROR: " + e.Message }

func newSyntaxErrorFromToken(t token) SyntaxError {
	var message string
	switch t.typ {
	case tokenUnenclosedString:
		message = "missing closing string double quotation mark"
	case tokenMalformedNumber:
		message = "malformed number: " + t.val
	default:
		panic("Called newSyntaxError with non-error type: " + t.typ.String())
	}

	return SyntaxError{t.pos, message}
}

func newUnexpectedClosingTokenError(t token) SyntaxError {
	return SyntaxError{
		Pos:     t.pos,
		Message: "unexpected '" + t.val + "'",
	}
}

func newUnexpectedTokenError(t token) SyntaxError {
	return SyntaxError{
		Pos:     t.pos,
		Message: "unexpected token '" + t.String() + "', value: " + t.val,
	}
}

// Created during expansion
type ExpansionError struct {
	Message string
}

func (e ExpansionError) Error() string {
	return "Expansion error: " + e.Message
}

func (e ExpansionError) Msg() string {
	return e.Message
}

// ELABORATION ERROR

type ElaborationError struct {
	Message string
}

func (e ElaborationError) Error() string {
	return "Elaboration error: " + e.Message
}

// RUNTIME ERROR

// Created by the evaluator
type RuntimeError struct {
	Message string
}

func (e RuntimeError) Error() string {
	return "Runtime error: " + e.Message
}

func (e RuntimeError) Msg() string {
	return e.Message
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
