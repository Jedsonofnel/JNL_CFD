package fvm

import (
	_ "embed"

	"github.com/Jedsonofnel/jnlcfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/linalg"
	jnl "jedn.dev/jnlisp"
)

//go:embed fvm.jnl
var nsSrc string

var NS = jnl.NewNamespace("jnl.cfd.fvm", nsSrc)

//
// jnlisp geometry bindings
//

func init() {
	jnl.CreatePredicate[*Equation](NS, "equation")
	NS.BindNativeFn(".new-equation", jnl.PosArity("mesh"), makeEquation)
	NS.BindNativeFn(".equation-zero", jnl.PosArity("eq"), equationZero)
	NS.BindNativeFn(".equation-solve", jnl.PosArity("eq", "solver", "field"), equationSolve)
	NS.BindNativeFn(".equation-solutions", jnl.PosArity("eq"), equationSolutions)
	NS.BindNativeFn(".equation-diagnostics", jnl.PosArity("eq"), equationDiagnostics)

	// operators
	NS.BindNativeFn(".laplacian-constant", jnl.PosArity("eq", "ctx", "gamma"), operatorLaplacianConstant)
	NS.BindNativeFn(".source-constant", jnl.PosArity("eq", "val"), operatorSourceConstant)

	// Boundary conditions
	NS.BindNativeFn(".bc-dirichlet-constant", jnl.PosArity("eq", "ctx", "bname", "val"), bcDirichletConstant)
	NS.BindNativeFn(".bc-neumann-constant", jnl.PosArity("eq", "ctx", "bname", "val"), bcNeumannConstant)
	NS.BindNativeFn(".bc-robin", jnl.PosArity("eq", "ctx", "bname", "h", "t_inf"), bcRobin)
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
	solver := jnl.GetNativeArg[linalg.Solver](ctx, "solver")
	field := jnl.GetArg[jnl.FloatTuple](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	eq.Solve(solver, field.Elements)
	return eq, nil
}

func equationDiagnostics(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	diagSum := 0.0
	for _, v := range eq.Diag {
		diagSum += v
	}

	sourceSum := 0.0
	for _, v := range eq.Source {
		sourceSum += v
	}

	minDiag := eq.Diag[0]
	maxDiag := eq.Diag[0]
	negativeCount := 0
	zeroCount := 0

	for _, v := range eq.Diag {
		if v < minDiag {
			minDiag = v
		}
		if v > maxDiag {
			maxDiag = v
		}
		if v < 0 {
			negativeCount++
		}
		if v == 0 {
			zeroCount++
		}
	}

	mapp := jnl.NewMap(
		"num-active-cells", len(eq.activeCells),
		"num-active-conns", len(eq.activeConnections),
		"num-boundary-conns", len(eq.boundaryConnections),
		"diagonal-sum", diagSum,
		"source-sum", sourceSum,
		"min-diag", minDiag,
		"max-diag", maxDiag,
		"num-negative-diags", negativeCount,
		"num-zero-diags", zeroCount,
	)

	return mapp, nil
}

func operatorLaplacianConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := ctx.GetMapArg()
	gammaKey := ctx.GetUnqualifiedKeyword()
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return LaplacianConstant(eq, context, gammaKey, AllRegions())
}

func operatorSourceConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	SourceConstant(eq, rat.Rational())
	return eq, nil
}

func bcDirichletConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return DirichletBC(eq, context, string(bname), rat.Rational())
}

func bcNeumannConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return NeumannBC(eq, context, string(bname), rat.Rational())
}

func bcRobin(ctx *jnl.CallContext) (jnl.Sexp, error) {
	eq := jnl.GetArg[*Equation](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	h := jnl.GetInterfaceArg[jnl.Rational](ctx, "h")
	tInf := jnl.GetInterfaceArg[jnl.Rational](ctx, "t_inf")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return RobinBC(eq, context, string(bname), h.Rational(), tInf.Rational())
}
