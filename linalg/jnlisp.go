package linalg

import (
	_ "embed"

	jnl "jedn.dev/jnlisp"
)

var NS *jnl.Namespace

//go:embed linalg.jnl
var nsSrc string

func init() {
	NS = jnl.NewNamespace("jnl.cfd.linalg", nsSrc)

	NS.BindNativeFn(".make-jacobi-cg", jnl.PosArity("ncells", "iters", "tolerance"), makeJacobiCG)
	NS.BindNativeFn(".make-simple-cg", jnl.PosArity("ncells", "iters", "tolerance"), makeSimpleCG)
}

func makeJacobiCG(ctx *jnl.CallContext) (jnl.Sexp, error) {
	numCells := jnl.GetArg[jnl.Int](ctx)
	maxIters := jnl.GetArg[jnl.Int](ctx)
	tolerance := jnl.GetArg[jnl.Float](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	solver := NewJacobiCG(int(numCells), int(maxIters), float64(tolerance))
	return jnl.Native{Value: solver, TypeName: "solver"}, nil
}

func makeSimpleCG(ctx *jnl.CallContext) (jnl.Sexp, error) {
	numCells := jnl.GetArg[jnl.Int](ctx)
	maxIters := jnl.GetArg[jnl.Int](ctx)
	tolerance := jnl.GetArg[jnl.Float](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	solver := NewSimpleCG(int(numCells), int(maxIters), float64(tolerance))
	return jnl.Native{Value: solver, TypeName: "solver"}, nil
}
