package fvm

import (
	"math"

	"jedn.dev/jnlcfd/geometry"
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

func (e Expression) ResolveInto(target []float64) {
	for i := range target {
		target[i] = e.Eval(i)
	}
}

//
// Factory functions for creating expressions with closures
//

func FieldExpr(field []float64) Expression {
	return Expression{
		Eval:    func(i int) float64 { return field[i] },
		IsConst: false,
	}
}

func ConstExpr(value float64) Expression {
	return Expression{
		Eval:    func(i int) float64 { return value },
		IsConst: true,
	}
}

// ScaleExpr multiplies an expression by a scalar constant.
func ScaleExpr(e Expression, alpha float64) Expression {
	if e.IsConst {
		val := e.Eval(0) * alpha
		return ConstExpr(val)
	}
	return Expression{
		Eval:    func(i int) float64 { return alpha * e.Eval(i) },
		IsConst: false,
	}
}

//
// Arithmetic operations with constant folding
//

func MulExpr(a, b Expression) Expression {
	return Expression{
		Eval:    func(i int) float64 { return a.Eval(i) * b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func AddExpr(a, b Expression) Expression {
	return Expression{
		Eval:    func(i int) float64 { return a.Eval(i) + b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func SubExpr(a, b Expression) Expression {
	return Expression{
		Eval:    func(i int) float64 { return a.Eval(i) - b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func DivExpr(a, b Expression) Expression {
	return Expression{
		Eval:    func(i int) float64 { return a.Eval(i) / b.Eval(i) },
		IsConst: a.IsConst && b.IsConst,
	}
}

func NegExpr(a Expression) Expression {
	return Expression{
		Eval:    func(i int) float64 { return -a.Eval(i) },
		IsConst: a.IsConst,
	}
}

func PowExpr(base Expression, exponent float64) Expression {
	return Expression{
		Eval:    func(i int) float64 { return math.Pow(base.Eval(i), exponent) },
		IsConst: base.IsConst,
	}
}

//
// Mesh and linalg cellwise values for use in expression
//

func CellVolExpr(mesh *geometry.Mesh) Expression {
	return Expression{
		Eval:    func(i int) float64 { return mesh.CellVolumes[i] },
		IsConst: false,
	}
}

func DiagExpr(sys *FVSystem) Expression {
	return Expression{
		Eval:    func(i int) float64 { return sys.Matrix.diag[i] },
		IsConst: false,
	}
}

//
// Expression mutation/application
//

// Apply collapses the expression: dst[i] = expr.Eval(i)
func (e Expression) Apply(dst []float64) {
	for i := range dst {
		dst[i] = e.Eval(i)
	}
}

// AddInto collapses the expression additively: dst[i] += expr.Eval(i)
func (e Expression) AddInto(dst []float64) {
	for i := range dst {
		dst[i] += e.Eval(i)
	}
}

// SubFrom collapses the expression subtractively: dst[i] -= expr.Eval(i)
func (e Expression) SubFrom(dst []float64) {
	for i := range dst {
		dst[i] -= e.Eval(i)
	}
}

// MulInto collapses the expression multiplicatively: dst[i] *= expr.Eval(i)
func (e Expression) MulInto(dst []float64) {
	for i := range dst {
		dst[i] *= e.Eval(i)
	}
}
