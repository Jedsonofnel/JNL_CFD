package jnlisp

import (
	"strconv"
)

type Error interface {
	error
	Msg() string
}

// IMPLEMENTATIONS
// TODO: consider adding a "Suggestion" field

// Combines multiple errors from different code blocks
type BlockErrors struct {
	Errors  []BlockError
	Message string
}

func (e BlockErrors) Error() string {
	return "Block errors:\n" + e.Message
}

func (e BlockErrors) Msg() string { return e.Message }

func newBlockErrors(blocks []Block) Error {
	var errors []BlockError
	message := ""

	for i := range blocks {
		errs := blocks[i].Errors
		if len(errs) == 0 {
			continue
		}

		for j := range errs {
			err := newBlockError(errs[j], i)
			errors = append(errors, err)
			message += "\t" + err.Error()
		}
	}

	if len(errors) == 0 {
		return nil
	}

	return BlockErrors{errors, message}
}

type BlockError struct {
	Err        Error
	BlockIndex int
}

func (e BlockError) Error() string {
	return "Error in block " + strconv.Itoa(e.BlockIndex) + ": " + e.Err.Error()
}

func (e BlockError) Msg() string { return e.Err.Error() }

func newBlockError(err Error, idx int) BlockError {
	return BlockError{err, idx}
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

func (e FileSystemError) Msg() string { return e.Message }

// SYNTAX ERROR

// Created during first parsing
type SyntaxError struct {
	Pos     Pos
	Message string
}

func (e SyntaxError) Error() string {
	return "Syntax error at " + e.Pos.String() + ": " + e.Message
}

func (e SyntaxError) Msg() string {
	return e.Message
}

func (e SyntaxError) ToJSON() string {
	return formatErrJSON("SyntaxError", e.Message, &e.Pos)
}

func newSyntaxErrorFromToken(t token) SyntaxError {
	var message string
	switch t.typ {
	case tokenMissingCloseList:
		message = "missing closing list parenthesis"
	case tokenMissingCloseVec:
		message = "missing closing vector bracket"
	case tokenMissingCloseString:
		message = "missing closing string double quotation mark"
	case tokenMalformedNumber:
		message = "malformed number: " + t.val
	case tokenInvalidLiteral:
		message = "invalid literal: " + t.val
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

// EXPANSION ERROR

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

func (e ElaborationError) Msg() string {
	return e.Message
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
