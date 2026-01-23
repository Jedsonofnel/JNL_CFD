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

	DirichletConstBC(sys, mesh, 0, "west")
	DirichletConstBC(sys, mesh, 100, "east")

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

func TestFaceInterpolation(t *testing.T) {
	mesh := geometry.MakeRectangular1DMesh(10)

	// Linear profile: φ = 100x (exact for CDS)
	field := make([]float64, 10)
	for i, c := range mesh.Centroids {
		field[i] = 100 * c.X
	}

	faceField := make([]float64, len(mesh.Connections))
	FaceInterpCDS(mesh, field, faceField)
	DirichletFaceValuesConst(mesh, faceField, "west", 0)
	DirichletFaceValuesConst(mesh, faceField, "east", 100)
	NeumannFaceValuesConst(mesh, field, faceField, "north", 0)
	NeumannFaceValuesConst(mesh, field, faceField, "south", 0)

	for i, conn := range mesh.Connections {
		var want float64
		if conn.Neighbour >= 0 {
			want = 100 * mesh.FaceCentroids[i].X // linear field → exact interp
		} else {
			switch mesh.BoundaryNames[int(-conn.Neighbour)] {
			case "west":
				want = 0
			case "east":
				want = 100
			default: // north/south: zero flux → face = owner
				want = field[conn.Owner]
			}
		}
		if !floatsEqual(faceField[i], want, FLOAT_TOL) {
			t.Errorf("face %d: got %v, want %v", i, faceField[i], want)
		}
	}
}

//
// Helpers
//

func floatsEqual(a, b, tol float64) bool {
	return math.Abs(a-b) <= tol
}
