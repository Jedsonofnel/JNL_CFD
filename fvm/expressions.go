package fvm

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
