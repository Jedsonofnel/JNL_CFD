package fvm

import (
	"math"
)

//
// Field arithmetic for arbitrary expressions
//

// Expressions are created with an evaluation function designed for
// initialising arbritrary arithmetic in an operator
type Expression struct {
	Eval    func(i int) float64
	IsConst bool
}

func FieldExpr(field []float64) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return field[i] },
		IsConst: false,
	}
}

func ConstExpr(value float64) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return value },
		IsConst: true,
	}
}

// Arithmetic operations with constant folding
func MulExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return a.Eval(i) * b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func AddExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return a.Eval(i) + b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func SubExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return a.Eval(i) - b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func DivExpr(a, b *Expression) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return a.Eval(i) / b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func NegExpr(a *Expression) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return -a.Eval(i) },
		IsConst: a.IsConst,
	}
}

func PowExpr(base *Expression, exponent float64) *Expression {
	return &Expression{
		Eval:    func(i int) float64 { return math.Pow(base.Eval(i), exponent) },
		IsConst: base.IsConst,
	}
}
