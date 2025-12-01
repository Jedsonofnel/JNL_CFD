package fvm

import (
	_ "embed"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	jnl "jedn.dev/jnlisp"
)

var NS *jnl.Namespace

//go:embed fvm.jnl
var nsSrc string

//
// jnlisp geometry bindings
//

func init() {
	NS = jnl.NewNamespace("jnl.cfd.fvm", nsSrc)

	jnl.CreatePredicate[*Field](NS, "field")
	NS.BindNativeFn(".field-is-scalar", jnl.PosArity("field"), fieldIsScalar)
	NS.BindNativeFn(".field-values", jnl.PosArity("field"), fieldValues)

	jnl.CreatePredicate[*Expression](NS, "expression")
	NS.BindNativeFn(".expr-field", jnl.PosArity("ctx", "str"), expressionField)
	NS.BindNativeFn(".expr-const", jnl.PosArity("float"), expressionConst)
	NS.BindNativeFn(".expr-mul", jnl.PosArity("e1", "e2"), expressionMul)
	NS.BindNativeFn(".expr-add", jnl.PosArity("e1", "e2"), expressionAdd)
	NS.BindNativeFn(".expr-sub", jnl.PosArity("e1", "e2"), expressionSub)
	NS.BindNativeFn(".expr-quot", jnl.PosArity("e1", "e2"), expressionQuot)

	jnl.CreatePredicate[*Context](NS, "context")
	NS.BindNativeFn(".make-context", jnl.PosArity("mesh"), makeContext)
	NS.BindNativeFn(".add-field", jnl.PosArity("ctx", "name", "vals"), contextAddField)
	NS.BindNativeFn(".add-uniform-field", jnl.PosArity("ctx", "name", "val"), contextAddUniformField)
	NS.BindNativeFn(".add-constant-field", jnl.PosArity("ctx", "name", "val"), contextAddConstantField)
	NS.BindNativeFn(
		".set-region-vals",
		jnl.PosArity("ctx", "fname", "regname", "val"),
		contextSetRegionValues,
	)

	jnl.CreatePredicate[*Equation](NS, "equation")
	NS.BindNativeFn(".make-equation", jnl.PosArity("mesh"), makeEquation)
	NS.BindNativeFn(".equation-zero", jnl.PosArity("eq"), equationZero)
	NS.BindNativeFn(".equation-solve", jnl.PosArity("eq", "solver", "ctx", "fname"), equationSolve)
	NS.BindNativeFn(".equation-solutions", jnl.PosArity("eq"), equationSolutions)

	// operators
	NS.BindNativeFn(".laplacian", jnl.PosArity("eq", "ctx", "phi", "gamma"), operatorLaplacian)
	NS.BindNativeFn(".source", jnl.PosArity("eq", "ctx", "phi", "su", "sp"), operatorSource)

	// Boundary conditions
	NS.BindNativeFn(".bc-dirichlet", jnl.PosArity("eq", "ctx", "bname", "val"), bcDirichlet)
	NS.BindNativeFn(".bc-neumann", jnl.PosArity("eq", "ctx", "bname", "val"), bcNeumann)
	NS.BindNativeFn(".bc-robin", jnl.PosArity("eq", "ctx", "bname", "alpha", "gamma"), bcRobin)

}

func (f *Field) String() string {
	return jnl.FormatNonReadable("cfd", "field")
}

func (f *Field) Type() string {
	return "field"
}

func (f *Field) Nth(i int) (jnl.Sexp, bool) {
	if f.Values == nil {
		return jnl.Float(f.Scalar), true
	}
	if i < 0 || i >= len(f.Values) {
		return jnl.Nil{}, false
	}
	return jnl.Float(f.Values[i]), true
}

func (f *Field) Length() int {
	return len(f.Values)
}

func (f *Field) GetName() string {
	return f.name
}

func fieldIsScalar(ctx *jnl.CallContext) (jnl.Sexp, error) {
	field := jnl.GetArg[*Field](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return jnl.Boolean(field.IsScalar()), nil
}

func fieldValues(ctx *jnl.CallContext) (jnl.Sexp, error) {
	field := jnl.GetArg[*Field](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	if field.Values == nil {
		return jnl.NewVector(jnl.Float(field.Scalar)), nil
	}

	elems := make([]jnl.Sexp, len(field.Values))
	for i := range field.Values {
		elems[i] = jnl.Float(field.Values[i])
	}
	return jnl.NewVector(elems...), nil
}

func (e *Expression) String() string {
	return jnl.FormatNonReadable("cfd", "expression")
}

func (e *Expression) Type() string {
	return "expression"
}

func expressionField(ctx *jnl.CallContext) (jnl.Sexp, error) {
	context := jnl.GetArg[*Context](ctx)
	field := jnl.GetArg[jnl.String](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return FieldExpr(context, string(field)), nil
}

func expressionConst(ctx *jnl.CallContext) (jnl.Sexp, error) {
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return jnl.Float(rat.Rational()), nil
}

func expressionMul(ctx *jnl.CallContext) (jnl.Sexp, error) {
	e1 := jnl.GetArg[*Expression](ctx)
	e2 := jnl.GetArg[*Expression](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return MulExpr(e1, e2), nil
}

func expressionAdd(ctx *jnl.CallContext) (jnl.Sexp, error) {
	e1 := jnl.GetArg[*Expression](ctx)
	e2 := jnl.GetArg[*Expression](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return AddExpr(e1, e2), nil
}

func expressionSub(ctx *jnl.CallContext) (jnl.Sexp, error) {
	e1 := jnl.GetArg[*Expression](ctx)
	e2 := jnl.GetArg[*Expression](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return SubExpr(e1, e2), nil
}

func expressionQuot(ctx *jnl.CallContext) (jnl.Sexp, error) {
	e1 := jnl.GetArg[*Expression](ctx)
	e2 := jnl.GetArg[*Expression](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return QuotExpr(e1, e2), nil
}

func (ctx *Context) String() string {
	return jnl.FormatNonReadable("cfd", "context")
}

func (ctx *Context) Type() string {
	return "context"
}

func (ctx *Context) Lookup(key jnl.Hashable) jnl.Sexp {
	str, ok := key.(jnl.String)
	if !ok {
		return jnl.Nil{}
	}

	if field, exists := ctx.Fields[string(str)]; exists {
		return field
	}

	return jnl.Nil{}
}

func (ctx *Context) Keys() []jnl.Hashable {
	strs := make([]jnl.Hashable, 0, len(ctx.Fields))
	for key := range ctx.Fields {
		strs = append(strs, jnl.String(key))
	}
	return strs
}

func makeContext(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*geometry.Mesh](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return NewContext(mesh), nil
}

func contextAddField(ctx *jnl.CallContext) (jnl.Sexp, error) {
	context := jnl.GetArg[*Context](ctx)
	name := jnl.GetArg[jnl.String](ctx)
	vals := jnl.GetArg[jnl.Vector](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	nVals := len(context.Mesh.Centroids)
	if vals.Length() != nVals {
		return nil, jnl.NewRTErr(
			jnl.ErrArgType,
			"'add-field' requires same number of vals as cells",
		)
	}
	values := make([]float64, nVals)
	for i := range values {
		val, _ := vals.Nth(i)
		rat, ok := val.(jnl.Rational)
		if !ok {
			return nil, jnl.NewRTErr(
				jnl.ErrArgType,
				"'add-field' requires rational values for cells",
			)
		}
		values[i] = rat.Rational()
	}
	context.AddField(string(name), values)
	return context, nil
}

func contextAddUniformField(ctx *jnl.CallContext) (jnl.Sexp, error) {
	context := jnl.GetArg[*Context](ctx)
	name := jnl.GetArg[jnl.String](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	context.AddUniformField(string(name), rat.Rational())
	return context, nil
}

func contextAddConstantField(ctx *jnl.CallContext) (jnl.Sexp, error) {
	context := jnl.GetArg[*Context](ctx)
	name := jnl.GetArg[jnl.String](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	context.AddConstantField(string(name), rat.Rational())
	return context, nil
}

func contextSetRegionValues(ctx *jnl.CallContext) (jnl.Sexp, error) {
	context := jnl.GetArg[*Context](ctx)
	fieldName := jnl.GetArg[jnl.String](ctx)
	regionName := jnl.GetArg[jnl.String](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	context.SetRegionValues(string(fieldName), string(regionName), rat.Rational())
	return context, nil
}

func (eq *Equation) String() string {
	return jnl.FormatNonReadable("cfd", "equation")
}

func (eq *Equation) Type() string {
	return "equation"
}

func makeEquation(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*geometry.Mesh](ctx)
	regions := jnl.GetVariadic[jnl.Keyword](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	regs := make([]string, len(regions))
	for i := range regs {
		regs[i] = regions[i].Name
	}
	return NewEquation(mesh, regs...), nil
}

func equationZero(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	eq.Zero()
	return eq, nil
}

func equationSolutions(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	vals := make([]jnl.Sexp, len(eq.solutions))
	for i := range vals {
		vals[i] = jnl.Float(eq.solutions[i])
	}
	return jnl.NewVector(vals...), nil
}

func equationSolve(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	solver := jnl.GetArg[*linalg.JacobiCG](ctx)
	context := jnl.GetArg[*Context](ctx)
	fieldName := jnl.GetArg[jnl.String](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	eq.Solve(solver, context, string(fieldName))
	return eq, nil
}

func operatorLaplacian(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := jnl.GetArg[*Context](ctx)
	phi := jnl.GetArg[jnl.String](ctx)
	gamma := jnl.GetArg[*Expression](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	LaplacianOperator(eq, context, string(phi), gamma, AllRegions())
	return eq, nil
}

func operatorSource(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := jnl.GetArg[*Context](ctx)
	phi := jnl.GetArg[jnl.String](ctx)
	su := jnl.GetArg[*Expression](ctx)
	sp := jnl.GetArg[*Expression](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	LinearSourceOperator(eq, context, string(phi), su, sp, AllRegions())
	return eq, nil
}

func bcDirichlet(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := jnl.GetArg[*Context](ctx)
	bname := jnl.GetArg[jnl.String](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	DirichletBC(eq, context, string(bname), rat.Rational())
	return eq, nil
}

func bcNeumann(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := jnl.GetArg[*Context](ctx)
	bname := jnl.GetArg[jnl.String](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	NeumannBC(eq, context, string(bname), rat.Rational())
	return eq, nil
}

func bcRobin(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := jnl.GetArg[*Context](ctx)
	bname := jnl.GetArg[jnl.String](ctx)
	alpha := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	gamma := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	RobinBC(eq, context, string(bname), alpha.Rational(), gamma.Rational())
	return eq, nil
}
