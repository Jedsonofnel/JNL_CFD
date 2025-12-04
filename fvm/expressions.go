package fvm

import (
	"errors"

	jnl "jedn.dev/jnlisp"
)

//
// Compiled field arithmetic for arbitrary expressions
//

// Expressions are created with an evaluation function designed for
// initialising arbritrary arithmetic in an operator
type Expression struct {
	Eval func(cellIdx int) float64
}

// FieldExpr gets the value of a field
func FieldExpr(ctx *Context, name string) *Expression {
	field := ctx.Fields[name]
	return &Expression{
		Eval: func(i int) float64 { return field.Get(i) },
	}
}

func ConstExpr(value float64) *Expression {
	return &Expression{
		Eval: func(i int) float64 { return value },
	}
}

func MulExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval: func(i int) float64 { return a.Eval(i) * b.Eval(i) },
	}
}

func AddExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval: func(i int) float64 { return a.Eval(i) + b.Eval(i) },
	}
}

func SubExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval: func(i int) float64 { return a.Eval(i) - b.Eval(i) },
	}
}

func QuotExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval: func(i int) float64 { return a.Eval(i) / b.Eval(i) },
	}
}

// GetExpression extracts a field from context and returns an Expression
func GetExpression(ctx jnl.Map, key string) (*Expression, error) {
	val := ctx.Lookup(jnl.NewKeyword(key))
	if val == (jnl.Nil{}) || val == nil {
		return nil, errors.New("field '" + key + "' not found in context")
	}

	switch v := val.(type) {
	case jnl.Float:
		// Constant scalar
		f := float64(v)
		return ConstExpr(f), nil
	case jnl.Int:
		// Integer constant
		f := float64(v)
		return ConstExpr(f), nil
	case jnl.FloatTuple:
		// Field array
		values := v.Elements
		return &Expression{
			Eval: func(i int) float64 { return values[i] },
		}, nil
	default:
		return nil, errors.New("cannot convert" + v.Type() + " to expression (key: " + key + ")")
	}
}
