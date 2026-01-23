package fvm

import (
	"math"
	"testing"

	"jedn.dev/jnlcfd/geometry"
)

const (
	FLOAT_TOL = 1e-9
	GAMMA     = 1
	RHO       = 1
)

func Test1DDiffusion(t *testing.T) {
	mesh := geometry.MakeRectangular1DMesh(10)
	field := make([]float64, 10)
	sys := NewFVSystem(mesh)

	LaplacianConstant(sys, mesh, GAMMA)

	DirichletBC(sys, mesh, 0, "west")
	DirichletBC(sys, mesh, 100, "east")

	sys.Solve(field, 1e-6, 100)

	for i, point := range mesh.Centroids {
		actual := 100 * point.X
		if got, want := field[i], actual; !floatsEqual(got, want, FLOAT_TOL) {
			t.Errorf("incorrect value at x=%v, got %v, wanted %v", point.X, field[i], actual)
			t.Logf("Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e",
				sys.DiagonalDominanceRatio(), sys.MaxAsymmetry(), sys.ResidualNorm(field))
			t.FailNow()
		}
	}
}

//
// Helpers
//

func floatsEqual(a, b, tol float64) bool {
	return math.Abs(a-b) <= tol
}
