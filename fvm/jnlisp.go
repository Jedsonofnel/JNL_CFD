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
	jnl.CreatePredicate[*LinearSystem](NS, "linear-system")
	NS.BindNativeFn(".new-linear-system", jnl.PosArity("mesh"), makeLinearSystem)
	NS.BindNativeFn(".sys-zero", jnl.PosArity("sys"), sysZero)
	NS.BindNativeFn(".sys-solve", jnl.PosArity("sys", "solver", "field"), sysSolve)
	NS.BindNativeFn(".sys-solutions", jnl.PosArity("sys"), sysSolutions)
	NS.BindNativeFn(".sys-diagnostics", jnl.PosArity("sys"), sysDiagnostics)

	// operators
	NS.BindNativeFn(".laplacian-constant", jnl.PosRestArity("sys", "ctx", "gamma", "regions"), operatorLaplacianConstant)
	NS.BindNativeFn(".source-constant", jnl.PosRestArity("sys", "ctx", "val", "regions"), operatorSourceConstant)

	// Boundary conditions
	NS.BindNativeFn(".bc-dirichlet-constant", jnl.PosArity("sys", "ctx", "bname", "val"), bcDirichletConstant)
	NS.BindNativeFn(".bc-neumann-constant", jnl.PosArity("sys", "ctx", "bname", "val"), bcNeumannConstant)
	NS.BindNativeFn(".bc-robin", jnl.PosArity("sys", "ctx", "bname", "h", "t_inf"), bcRobin)

	// Rendering
	NS.BindNativeFn(".update-tri-field", jnl.PosArity("results", "tri-to-cells"), updateTriField)
}

func (sys *LinearSystem) String() string {
	return jnl.FormatNonReadable("cfd", "linear-system")
}

func (sys *LinearSystem) Type() string {
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
	regions := jnl.GetVariadic[jnl.Keyword](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	regionStrs := make([]string, len(regions))
	for i, r := range regions {
		regionStrs[i] = r.Name
	}

	if err := LaplacianConstant(sys, context, gammaKey, regionStrs...); err != nil {
		return nil, err
	}
	return sys, nil
}

func operatorSourceConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	context := ctx.GetMapArg()
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	regions := jnl.GetVariadic[jnl.Keyword](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	regionStrs := make([]string, len(regions))
	for i, r := range regions {
		regionStrs[i] = r.Name
	}

	if err := SourceConstant(sys, context, rat.Rational(), regionStrs...); err != nil {
		return nil, err
	}
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

	if err := DirichletBC(sys, context, bname, rat.Rational()); err != nil {
		return nil, err
	}
	return sys, nil
}

func bcNeumannConstant(ctx *jnl.CallContext) (jnl.Sexp, error) {
	sys := jnl.GetArg[*LinearSystem](ctx)
	context := ctx.GetMapArg()
	bname := ctx.GetUnqualifiedKeyword()
	rat := jnl.GetInterfaceArg[jnl.Rational](ctx, "rational")
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	if err := NeumannBC(sys, context, bname, rat.Rational()); err != nil {
		return nil, err
	}
	return sys, nil
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

	hVal := h.Rational()
	gamma := hVal * tInf.Rational()

	if err := RobinBC(sys, context, bname, hVal, gamma); err != nil {
		return nil, err
	}
	return sys, nil
}

func updateTriField(ctx *jnl.CallContext) (jnl.Sexp, error) {
	results := jnl.GetArg[jnl.FloatTuple](ctx)
	triToCells := jnl.GetArg[jnl.IntTuple](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	triField := make([]float64, len(triToCells.Elements)*3)
	err := UpdateTriField(triField, results.Elements, triToCells.Elements)
	if err != nil {
		return nil, err
	}

	return jnl.NewFloatTuple(triField), nil
}
