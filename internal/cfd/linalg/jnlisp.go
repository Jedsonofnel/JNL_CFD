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

	NS.BindNativeFn(".make-jacobi-cg", jnl.PosArity("ncells", "iters", "tolerance"), makeJacobi)
}

func (cg *JacobiCG) String() string {
	return jnl.FormatNonReadable("solver", "jacobi-cg")
}

func (cg *JacobiCG) Type() string {
	return "solver"
}

func makeJacobi(ctx *jnl.CallContext) (jnl.Sexp, error) {
	numCells := jnl.GetArg[jnl.Int](ctx)
	maxIters := jnl.GetArg[jnl.Int](ctx)
	tolerance := jnl.GetArg[jnl.Float](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	return NewJacobiCG(int(numCells), int(maxIters), float64(tolerance)), nil
}
