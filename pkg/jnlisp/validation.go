package jnlisp

import (
	"fmt"
	"strings"
)

// Argument validation helpers
type ArgValidator struct {
	args     []Atom
	kwargs   Table
	argIndex int
	errors   []string
}

func ValidateArgs(args []Atom, kwargs Table) *ArgValidator {
	return &ArgValidator{args: args, kwargs: kwargs}
}

func (av *ArgValidator) GetString() (string, *ArgValidator) {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, fmt.Sprintf("missing positional arg at index %d", av.argIndex))
		return "", av
	}

	if str, ok := As[StringAtom](av.args[av.argIndex]); ok {
		return str.value, av
	}

	av.errors = append(av.errors, fmt.Sprintf("arg %d: expected string, got %s",
		av.argIndex, av.args[av.argIndex].Type()))
	av.argIndex++
	return "", av
}

func (av *ArgValidator) GetInt() (int, *ArgValidator) {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, fmt.Sprintf("missing positional arg %d (expected number)", av.argIndex))
		return 0, av
	}

	if num, ok := As[NumberAtom](av.args[av.argIndex]); ok {
		av.argIndex++
		if i, ok := num.value.(int); ok {
			return i, av
		}
	}

	av.errors = append(av.errors, fmt.Sprintf("arg %d: expected integer, got %s",
		av.argIndex, av.args[av.argIndex].Type()))
	av.argIndex++
	return 0, av
}

func (av *ArgValidator) GetFloat64() (float64, *ArgValidator) {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, fmt.Sprintf("missing positional arg %d (expected number)", av.argIndex))
		return 0, av
	}

	if num, ok := As[NumberAtom](av.args[av.argIndex]); ok {
		av.argIndex++
		if f, ok := num.value.(float64); ok {
			return f, av
		}
		if f, ok := num.value.(float32); ok {
			return float64(f), av
		}
		if i, ok := num.value.(int); ok {
			return float64(i), av
		}
	}

	av.errors = append(av.errors, fmt.Sprintf("arg %d: expected number, got %s",
		av.argIndex, av.args[av.argIndex].Type()))
	av.argIndex++
	return 0, av
}

func (av *ArgValidator) GetVector() (VectorAtom, *ArgValidator) {
	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, fmt.Sprintf("missing positional arg %d (expected vector)",
			av.argIndex))
		return VectorAtom{}, av
	}

	if vec, ok := As[VectorAtom](av.args[av.argIndex]); ok {
		av.argIndex++
		return vec, av
	}

	av.errors = append(av.errors, fmt.Sprintf("arg %d: expected vector, got %s",
		av.argIndex, av.args[av.argIndex].Type()))
	av.argIndex++
	return VectorAtom{}, av
}

func Get[T Atom](av *ArgValidator) (T, *ArgValidator) {
	var zero T

	if av.argIndex >= len(av.args) {
		av.errors = append(av.errors, fmt.Sprintf("missing positional arg %d (expected %T)",
			av.argIndex, zero))
		return zero, av
	}

	if result, ok := As[T](av.args[av.argIndex]); ok {
		av.argIndex++
		return result, av
	}

	av.errors = append(av.errors, fmt.Sprintf("arg %d: expected %T, got %s",
		av.argIndex, zero, av.args[av.argIndex].Type()))
	av.argIndex++
	return zero, av
}

func (av *ArgValidator) ExpectNoMoreArgs() *ArgValidator {
	if av.argIndex < len(av.args) {
		av.errors = append(av.errors, fmt.Sprintf("unexpected extra arguments: expected %d, got %d",
			av.argIndex, len(av.args)))
	}
	return av
}

// VARIADIC ARGS

func (av *ArgValidator) GetVariadicFloat32() ([]float32, *ArgValidator) {
	var floats []float32

	// Process all remaining positional arguments
	for av.argIndex < len(av.args) {
		if num, ok := As[NumberAtom](av.args[av.argIndex]); ok {
			switch v := num.value.(type) {
			case float64:
				floats = append(floats, float32(v))
			case float32:
				floats = append(floats, v)
			case int:
				floats = append(floats, float32(v))
			default:
				av.errors = append(av.errors, fmt.Sprintf("arg %d: cannot convert %T to float64",
					av.argIndex, v))
				av.argIndex++
				continue
			}
		} else {
			av.errors = append(av.errors, fmt.Sprintf("arg %d: expected number, got %s", av.argIndex, av.args[av.argIndex].Type()))
			av.argIndex++
			continue
		}
		av.argIndex++
	}

	return floats, av
}

func (av *ArgValidator) GetVariadicComplex128() ([]complex128, *ArgValidator) {
	var complexes []complex128

	// Process all remaining positional arguments
	for av.argIndex < len(av.args) {
		if num, ok := As[NumberAtom](av.args[av.argIndex]); ok {
			switch v := num.value.(type) {
			case float64:
				complexes = append(complexes, complex(v, 0))
			case float32:
				complexes = append(complexes, complex(float64(v), 0))
			case int:
				complexes = append(complexes, complex(float64(v), 0))
			case complex128:
				complexes = append(complexes, v)
			default:
				av.errors = append(av.errors, fmt.Sprintf("arg %d: cannot convert %T to complex",
					av.argIndex, v))
				av.argIndex++
				continue
			}
		} else {
			av.errors = append(av.errors, fmt.Sprintf("arg %d: expected number, got %s", av.argIndex, av.args[av.argIndex].Type()))
			av.argIndex++
			continue
		}
		av.argIndex++
	}

	return complexes, av
}

// KEYWORD ARGS

func (av *ArgValidator) GetKeywordInt(key string) (int, *ArgValidator) {
	atom, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, fmt.Sprintf("missing required keyword: %s", key))
		return 0, av
	}

	if num, ok := As[NumberAtom](atom); ok {
		if i, ok := num.value.(int); ok {
			return i, av
		}
	}

	av.errors = append(av.errors, fmt.Sprintf("keyword %s: expected number, got %s",
		key, atom.Type()))
	return 0, av
}

func (av *ArgValidator) GetKeywordFloat32(key string) (float32, *ArgValidator) {
	atom, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, fmt.Sprintf("missing required keyword: %s", key))
		return 0, av
	}

	if num, ok := As[NumberAtom](atom); ok {
		if i, ok := num.value.(int); ok {
			return float32(i), av
		}
		if f, ok := num.value.(float64); ok {
			return float32(f), av
		}
		if f, ok := num.value.(float32); ok {
			return f, av
		}
	}

	av.errors = append(av.errors, fmt.Sprintf("keyword %s: expected number, got %s",
		key, atom.Type()))
	return 0, av
}

func (av *ArgValidator) GetKeywordFloat64(key string) (float64, *ArgValidator) {
	atom, exists := av.kwargs[key]
	if !exists {
		av.errors = append(av.errors, fmt.Sprintf("missing required keyword: %s", key))
		return 0, av
	}

	if num, ok := As[NumberAtom](atom); ok {
		if i, ok := num.value.(int); ok {
			return float64(i), av
		}
		if f, ok := num.value.(float64); ok {
			return f, av
		}
		if f, ok := num.value.(float32); ok {
			return float64(f), av
		}
	}

	av.errors = append(av.errors, fmt.Sprintf("keyword %s: expected number, got %s", key, atom.Type()))
	return 0, av
}

func (av *ArgValidator) Validate() error {
	if len(av.errors) > 0 {
		return fmt.Errorf("argument validation failed: %s", strings.Join(av.errors, "; "))
	}
	return nil
}
