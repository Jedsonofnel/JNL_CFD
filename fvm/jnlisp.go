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
	jnl.CreatePredicate[*LinearSystem](NS, "equation")
	NS.BindNativeFn(".new-linear-system", jnl.PosArity("mesh"), makeLinearSystem)
	NS.BindNativeFn(".sys-zero", jnl.PosArity("eq"), sysZero)
	NS.BindNativeFn(".sys-solve", jnl.PosArity("eq", "solver", "field"), sysSolve)
	NS.BindNativeFn(".sys-solutions", jnl.PosArity("eq"), sysSolutions)
	NS.BindNativeFn(".sys-diagnostics", jnl.PosArity("eq"), sysDiagnostics)

	// operators
	NS.BindNativeFn(".laplacian-constant", jnl.PosArity("eq", "ctx", "gamma"), operatorLaplacianConstant)
	NS.BindNativeFn(".source-constant", jnl.PosArity("eq", "val"), operatorSourceConstant)

	// Boundary conditions
	NS.BindNativeFn(".bc-dirichlet-constant", jnl.PosArity("eq", "ctx", "bname", "val"), bcDirichletConstant)
	NS.BindNativeFn(".bc-neumann-constant", jnl.PosArity("eq", "ctx", "bname", "val"), bcNeumannConstant)
	NS.BindNativeFn(".bc-robin", jnl.PosArity("eq", "ctx", "bname", "h", "t_inf"), bcRobin)
}

func (eq *LinearSystem) String() string {
	return jnl.FormatNonReadable("cfd", "linear-system")
}

func (eq *LinearSystem) Type() string {
	return "linear-system"
}

func makeLinearSystem(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*geometry.Mesh](ctx)
	regions := jnl.GetVariadic[jnl.Keyword](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	regs := make([]string, len(regions))
	for i := range regs {
		regs[i] = regions[i].Name
	}
	return NewLinearSystem(mesh, regs...), nil
}

func sysZero(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	sys.Zero()
	return sys, nil
}

func sysSolutions(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	vals := make([]jnl.Sexp, len(sys.solutions))
	for i := range vals {
		vals[i] = jnl.Float(sys.solutions[i])
	}
	return jnl.NewVector(vals...), nil
}

func sysSolve(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	solver := jnl.GetNativeArg[linalg.Solver](ctx, "solver")
	field := jnl.GetArg[jnl.FloatTuple](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	sys.Solve(solver, field.Elements)
	return sys, nil
}

func sysDiagnostics(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	diagSum := 0.0
	for _, v := range sys.Diag {
		diagSum += v
	}

	sourceSum := 0.0
	for _, v := range sys.Source {
		sourceSum += v
	}

	minDiag := sys.Diag[0]
	maxDiag := sys.Diag[0]
	negativeCount := 0
	zeroCount := 0

	for _, v := range sys.Diag {
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
		"num-active-cells", len(sys.activeCells),
		"num-active-conns", len(sys.activeConnections),
		"num-boundary-conns", len(sys.boundaryConnections),
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
	sys := jnl.GetArg[*LinearSystem](ctx)
	context := ctx.GetMapArg()
	gammaKey := ctx.GetUnqualifiedKeyword()
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return LaplacianConstant(sys, context, gammaKey, AllRegions())
}

func operatorSourceConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	SourceConstant(sys, rat.Rational())
	return sys, nil
}

func bcDirichletConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return DirichletBC(sys, context, string(bname), rat.Rational())
}

func bcNeumannConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return NeumannBC(sys, context, string(bname), rat.Rational())
}

func bcRobin(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	h := jnl.GetInterfaceArg[jnl.Rational](ctx, "h")
	tInf := jnl.GetInterfaceArg[jnl.Rational](ctx, "t_inf")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return RobinBC(sys, context, string(bname), h.Rational(), tInf.Rational())
}
