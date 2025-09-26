package linalg

import (
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

func init() {
	jnlisp.RegisterLibrary(jnlisp.Library{
		Name:     "cfd/linalg",
		Bindings: map[string]jnlisp.ProcFunc{
			"jacobi-preconditioned-cg": lispJacobiCG,
		},
		Atoms:    map[string]jnlisp.Atom{},
	})
}

// SOLVERS

type SolverDefinitionAtom struct{ Value SolverDefinition }

func (fd SolverDefinitionAtom) Type() string {
	return "cfd/linalg.SolverDefinition"
}

func (fd SolverDefinitionAtom) String() string {
	return "cfd/linalg.SolverDefinition"
}

func (fd SolverDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  fd.Type(),
		"value": "INTERFACE TYPE",
		"repr":  fd.String(),
	}
}

func lispJacobiCG(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs)
	maxIters, v := v.GetKeywordInt("max-iterations")
	tolerance, v := v.GetKeywordFloat32("tolerance")

	v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	solver := NewJacobiCG(maxIters, tolerance)
	return SolverDefinitionAtom{solver}, nil
}
