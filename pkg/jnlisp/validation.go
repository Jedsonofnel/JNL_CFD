package jnlisp

import (
	"strconv"
	"strings"
)

// Argument validation helpers
type ArgValidator struct {
	args           []Sexp
	kwargs         Table
	argIndex       int
	consumedKwargs map[string]bool
	errors         []string
}

func ValidateArgs(args []Sexp, kwargs Table) *ArgValidator {
	return &ArgValidator{
		args:           args,
		kwargs:         kwargs,
		consumedKwargs: make(map[string]bool),
	}
}

func (av *ArgValidator) GetString() string {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, "string"))
		return ""
	}

	if str, ok := av.args[av.argIndex].(String); ok {
		av.argIndex++
		return string(str)
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, "string", av.args[av.argIndex].Type()))
	av.argIndex++
	return ""
}

func (av *ArgValidator) GetInt() int {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, "integer"))
		return 0
	}

	if num, ok := av.args[av.argIndex].(Number); ok {
		av.argIndex++
		if i, ok := num.ToInt(); ok {
			return i
		}
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, "integer", av.args[av.argIndex].Type()))
	av.argIndex++
	return 0
}

func (av *ArgValidator) GetFloat64() float64 {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, "number"))
		return 0
	}

	if num, ok := av.args[av.argIndex].(Number); ok {
		av.argIndex++
		if f, ok := num.ToFloat64(); ok {
			return f
		}
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, "number", av.args[av.argIndex].Type()))
	av.argIndex++
	return 0
}

func (av *ArgValidator) GetFloat32() float32 {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, "number"))
		return 0
	}

	if num, ok := av.args[av.argIndex].(Number); ok {
		av.argIndex++
		if f, ok := num.ToFloat64(); ok {
			return float32(f)
		}
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, "number", av.args[av.argIndex].Type()))
	av.argIndex++
	return 0
}

func (av *ArgValidator) GetVector() Vector {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, "vector"))
		return nil
	}

	if vec, ok := av.args[av.argIndex].(Vector); ok {
		av.argIndex++
		return vec
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, "vector", av.args[av.argIndex].Type()))
	av.argIndex++
	return nil
}

func (av *ArgValidator) GetFunction() Function {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, "function"))
		return nil
	}

	if proc, ok := av.args[av.argIndex].(Function); ok {
		av.argIndex++
		return proc
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, "function", av.args[av.argIndex].Type()))
	av.argIndex++
	return nil
}

func Get[T Sexp](av *ArgValidator) T {
	var zero T

	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, missingArgErr(av.argIndex, zero.Type()))
		return zero
	}

	if result, ok := av.args[av.argIndex].(T); ok {
		av.argIndex++
		return result
	}

	av.errors = append(av.errors, argTypeErr(av.argIndex, zero.Type(), av.args[av.argIndex].Type()))
	av.argIndex++
	return zero
}

// VARIADIC ARGS

func (av *ArgValidator) GetVariadicFloat32() []float32 {
	var floats []float32

	// Process all remaining positional arguments
	for av.argIndex < len(av.args) {
		if num, ok := av.args[av.argIndex].(Number); ok {
			if f, ok := num.ToFloat64(); ok {
				floats = append(floats, float32(f))
			} else {
				av.errors = append(av.errors, "arg "+strconv.Itoa(av.argIndex)+
					" cannot convert to float64")
				continue
			}
		} else {
			av.errors = append(av.errors, argTypeErr(av.argIndex, "number", av.args[av.argIndex].Type()))
			av.argIndex++
			continue
		}
		av.argIndex++
	}

	return floats
}

func (av *ArgValidator) GetVariadicFloat64() []float64 {
	var floats []float64

	// Process all remaining positional arguments
	for av.argIndex < len(av.args) {
		if num, ok := av.args[av.argIndex].(Number); ok {
			if f, ok := num.ToFloat64(); ok {
				floats = append(floats, f)
			} else {
				av.errors = append(av.errors, "arg "+strconv.Itoa(av.argIndex)+
					" cannot convert to float64")
				continue
			}
		} else {
			av.errors = append(av.errors, argTypeErr(av.argIndex, "number", av.args[av.argIndex].Type()))
			av.argIndex++
			continue
		}
		av.argIndex++
	}

	return floats
}

func (av *ArgValidator) GetVariadicComplex128() []complex128 {
	var complexes []complex128

	// Process all remaining positional arguments
	for av.argIndex < len(av.args) {
		if num, ok := av.args[av.argIndex].(Number); ok {
			complexes = append(complexes, num.ToComplex128())
		} else {
			av.errors = append(av.errors, argTypeErr(av.argIndex, "number", av.args[av.argIndex].Type()))
			av.argIndex++
			continue
		}
		av.argIndex++
	}

	return complexes
}

func (av *ArgValidator) GetVariadicSexps() []Sexp {
	var sexps []Sexp

	for av.argIndex < len(av.args) {
		sexps = append(sexps, av.args[av.argIndex])
		av.argIndex++
	}

	return sexps
}

func GetVariadic[T Sexp](av *ArgValidator) []T {
	var zero T
	var sexps []T

	for av.argIndex < len(av.args) {
		if arg, ok := av.args[av.argIndex].(T); ok {
			sexps = append(sexps, arg)
		} else {
			av.errors = append(av.errors, argTypeErr(
				av.argIndex, zero.Type(), av.args[av.argIndex].Type()))
		}
		av.argIndex++
	}

	return sexps
}

// KEYWORD ARGS

func (av *ArgValidator) GetKeywordInt(key string) int {
	sexp, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, missingKwargErr(key))
		return 0
	}

	av.consumedKwargs[key] = true

	if num, ok := sexp.(Number); ok {
		if i, ok := num.ToInt(); ok {
			return i
		}
	}

	av.errors = append(av.errors, kwargTypeErr(key, "number", sexp.Type()))
	return 0
}

func (av *ArgValidator) GetKeywordFloat32(key string) float32 {
	sexp, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, missingKwargErr(key))
		return 0
	}

	av.consumedKwargs[key] = true

	if num, ok := sexp.(Number); ok {
		if i, ok := num.ToFloat64(); ok {
			return float32(i)
		}
	}

	av.errors = append(av.errors, kwargTypeErr(key, "number", sexp.Type()))
	return 0
}

func (av *ArgValidator) GetKeywordFloat64(key string) float64 {
	sexp, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, missingKwargErr(key))
		return 0
	}

	av.consumedKwargs[key] = true

	if num, ok := sexp.(Number); ok {
		if f, ok := num.ToFloat64(); ok {
			return f
		}
	}

	av.errors = append(av.errors, kwargTypeErr(key, "number", sexp.Type()))
	return 0
}

func (av *ArgValidator) GetKeywordVector(key string) Vector {
	sexp, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, missingKwargErr(key))
		return nil
	}

	av.consumedKwargs[key] = true

	if vec, ok := sexp.(Vector); ok {
		return vec
	}

	av.errors = append(av.errors, kwargTypeErr(key, "vector", sexp.Type()))
	return nil
}

func GetKeyword[T Sexp](av *ArgValidator, key string) T {
	var zero T

	sexp, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, missingKwargErr(key))
		return zero
	}

	av.consumedKwargs[key] = true

	if a, ok := sexp.(T); ok {
		return a
	}

	av.errors = append(av.errors, kwargTypeErr(key, zero.Type(), sexp.Type()))
	return zero
}

// VALIDATION

func (av *ArgValidator) ExpectNoMoreArgs() {
	if av.argIndex < len(av.args) {
		av.errors = append(av.errors, "unexpected extra arguments ("+
			av.args[av.argIndex].String()+"): expected "+
			strconv.Itoa(av.argIndex)+"got "+strconv.Itoa(len(av.args)))
	}

	for key := range av.kwargs {
		if !av.consumedKwargs[key] {
			av.errors = append(av.errors, "unexpected keyword argument: "+key)
		}
	}
}

func (av *ArgValidator) Validate(funcName string) Error {
	if len(av.errors) > 0 {
		return RuntimeError{
			Message: funcName + " argument validation failed: " + strings.Join(av.errors, "; "),
		}
	}
	return nil
}

// ERROR HELPERS

func argTypeErr(index int, expected, got string) string {
	return "arg " + strconv.Itoa(index) + ": expected " + expected + ", got " + got
}

func missingArgErr(index int, expectedType string) string {
	return "missing positional arg " + strconv.Itoa(index) + " (expected " + expectedType + ")"
}

func kwargTypeErr(key, expected, got string) string {
	return "keyword " + key + ": expected " + expected + ", got " + got
}

func missingKwargErr(key string) string {
	return "missing required keyword: " + key
}
