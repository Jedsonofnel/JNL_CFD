package jnlisp

import (
	"strconv"
)

type Error interface {
	error
}

type ErrorCode int

// Error codes for all types of errors
const (
	// syntax errors
	ErrMissingDelimiter ErrorCode = iota
	ErrUnexpectedDelimiter
	ErrUnexpectedToken
	ErrMalformedNumber
	ErrUnenclosedString
	ErrDuplicateMapKeys
	ErrExpectedKeyValue // when a keyword isn't followed by a value
	ErrExpectedKeyword  // when it's not a keyword in a map

	expansion_errors // sentinal value
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

// Created by the parser - implements Sexp
type SyntaxError struct {
	Code    ErrorCode
	token   token
	Message string
}

func (e SyntaxError) Error() string {
	return "Syntax error at " + e.token.pos.String() + ": " + e.Message
}

func (e SyntaxError) ToJSON() string {
	return formatErrJSON("SyntaxError", e.Message, &e.token.pos)
}

func (e SyntaxError) Type() string   { return "error" }
func (e SyntaxError) String() string { return "ERROR: " + e.Message }

func newErrMissingDelimiter(t token, delim string) SyntaxError {
	return SyntaxError{
		Code:    ErrMissingDelimiter,
		token:   t,
		Message: "missing delimiter: '" + delim + "'",
	}
}

func newErrUnexpectedDelimiter(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrUnexpectedDelimiter,
		token:   t,
		Message: "unexpected delimeter: '" + t.val + "'",
	}
}

func newErrUnexpectedToken(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrUnexpectedToken,
		token:   t,
		Message: "unexpected token: '" + t.val + "'",
	}
}

func newErrMalformedNumber(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrMalformedNumber,
		token:   t,
		Message: "malformed number: '" + t.val + "'",
	}
}

func newErrUnenclosedString(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrUnenclosedString,
		token:   t,
		Message: "unenclosed string: '" + t.val + "'",
	}
}

func newErrDuplicateMapKeys(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrDuplicateMapKeys,
		token:   t,
		Message: "duplicate map key: '" + t.val + "'",
	}
}

func newErrExpectedKeyValue(t token, key string) SyntaxError {
	return SyntaxError{
		Code:    ErrExpectedKeyValue,
		token:   t,
		Message: "expected value for key: '" + key + "'",
	}
}

func newErrExpectedKeyword(t token) SyntaxError {
	return SyntaxError{
		Code:    ErrExpectedKeyword,
		token:   t,
		Message: "expected keyword in map, got: '" + t.val + "'",
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
