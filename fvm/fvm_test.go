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
	field, mesh, sys := CaseDiffusion1D(10, GAMMA)

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

func TestGreenGaussGradient(t *testing.T) {
	mesh := geometry.MakeRectangular1DMesh(10)

	// Linear profile: φ = 100x → ∇φ = (100, 0)
	field := make([]float64, 10)
	for i, c := range mesh.Centroids {
		field[i] = 100 * c.X
	}

	faceField := make([]float64, len(mesh.Connections))
	gradX := make([]float64, 10)
	gradY := make([]float64, 10)

	FaceInterpCDS(mesh, field, faceField)
	DirichletFaceValuesConst(mesh, faceField, "west", 0)
	DirichletFaceValuesConst(mesh, faceField, "east", 100)
	NeumannFaceValuesConst(mesh, field, faceField, "north", 0)
	NeumannFaceValuesConst(mesh, field, faceField, "south", 0)

	GreenGaussGradient(mesh, faceField, gradX, gradY)

	for i := range field {
		if !floatsEqual(gradX[i], 100, FLOAT_TOL) {
			t.Errorf("cell %d: gradX = %v, want 100", i, gradX[i])
		}
		if !floatsEqual(gradY[i], 0, FLOAT_TOL) {
			t.Errorf("cell %d: gradY = %v, want 0", i, gradY[i])
		}
	}
}

func TestGreenGaussGradientDiagonal(t *testing.T) {
	mesh := geometry.MakeRectangular1DMesh(10)

	// φ = 3x + 7y → ∇φ = (3, 7)
	field := make([]float64, 10)
	for i, c := range mesh.Centroids {
		field[i] = 3*c.X + 7*c.Y
	}

	faceField := make([]float64, len(mesh.Connections))
	gradX := make([]float64, 10)
	gradY := make([]float64, 10)

	// All boundaries: extrapolate from linear field
	FaceInterpCDS(mesh, field, faceField)
	for i, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			fc := mesh.FaceCentroids[i]
			faceField[i] = 3*fc.X + 7*fc.Y
		}
	}

	GreenGaussGradient(mesh, faceField, gradX, gradY)

	for i := range field {
		if !floatsEqual(gradX[i], 3, FLOAT_TOL) {
			t.Errorf("cell %d: gradX = %v, want 3", i, gradX[i])
		}
		if !floatsEqual(gradY[i], 7, FLOAT_TOL) {
			t.Errorf("cell %d: gradY = %v, want 7", i, gradY[i])
		}
	}
}

func Test1DConvectionDiffusion(t *testing.T) {
	velocity := 1.0
	phi, mesh, sys := CaseConvectionDiffusion1D(10, GAMMA, RHO, velocity)

	for i, point := range mesh.Centroids {
		actual := calculate1DAnalytical(mesh.Centroids[i].X, 1, velocity, RHO, GAMMA, 0, 100)

		if got, want := phi[i], actual; !floatsEqual(got, want, 5e-1) {
			t.Errorf("incorrect value at x=%v, got %v, wanted %v", point.X, phi[i], actual)
			t.Logf("Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e",
				sys.DiagonalDominanceRatio(), sys.MaxAsymmetry(), sys.ResidualNorm(phi))
			t.FailNow()
		}
	}
}

func TestPoiseuilleGivenPressure(t *testing.T) {
	Uy, mesh, _ := CasePoiseuilleGivenPressure(10, GAMMA, 10)

	for i, point := range mesh.Centroids {
		t.Logf("x=%v, Uy=%v", point.X, Uy[i])
	}
	// actually need to compare against poiseuille flow equation but the
	// logf values are symmetric and parabolic which is exciting!
	t.Fatalf("TODO: Test")
}

//
// Helpers
//

func floatsEqual(a, b, tol float64) bool {
	return math.Abs(a-b) <= tol
}

func calculate1DAnalytical(x, length, ux, rho, gamma, phi_0, phi_L float64) float64 {
	// peclet number
	Pe := rho * ux * length / gamma

	if math.Abs(Pe) < 1e-10 { // pure diffusion therefore linear profile
		return phi_0 + (x/length)*(phi_L-phi_0)
	}
	coeff := (math.Exp(Pe*x/length) - 1) / (math.Exp(Pe) - 1)
	return phi_0 + coeff*(phi_L-phi_0)
}
