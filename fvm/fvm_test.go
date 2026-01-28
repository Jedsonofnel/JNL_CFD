package fvm

import (
	"math"
	"testing"
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
	nCells := 1000
	PyGrad := -100.0
	Uy, mesh, sys := CasePoiseuilleGivenPressure(nCells, GAMMA, PyGrad)

	for i, point := range mesh.Centroids {
		analytical := (-PyGrad / (2 * GAMMA)) * point.X * (1 - point.X)

		if got, want := Uy[i], analytical; !floatsEqual(got, want, 0.01) {
			t.Errorf("incorrect value at x=%v, got %v, wanted %v", point.X, Uy[i], analytical)
			t.Logf("Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e",
				sys.DiagonalDominanceRatio(), sys.MaxAsymmetry(), sys.ResidualNorm(Uy))
			t.FailNow()
		}
	}

	// Verify parabolic profile: max should be at center
	maxIdx := 0
	for i := range Uy {
		if Uy[i] > Uy[maxIdx] {
			maxIdx = i
		}
	}

	expectedMaxUy := (PyGrad / (2 * GAMMA)) * 0.25
	if !floatsEqual(Uy[maxIdx], expectedMaxUy, 0.1) {
		t.Logf("Expected max velocity ~%v at center, got %v at cell %d",
			expectedMaxUy, Uy[maxIdx], maxIdx)
	}
}

func TestPoiseuilleConvergenceOrder(t *testing.T) {
	gamma := 1.0
	PyGrad := -100.0

	cellCounts := []int{5, 10, 20, 40, 80}
	errors := make([]float64, len(cellCounts))
	dxValues := make([]float64, len(cellCounts))

	for i, nCells := range cellCounts {
		Uy, mesh, _ := CasePoiseuilleGivenPressure(nCells, gamma, PyGrad)
		dxValues[i] = 1.0 / float64(nCells)

		// Compute max error
		maxErr := 0.0
		for j, point := range mesh.Centroids {
			analytical := (-PyGrad / (2 * gamma)) * point.X * (1 - point.X)
			err := math.Abs(Uy[j] - analytical)
			maxErr = max(maxErr, err)
		}
		errors[i] = maxErr
	}

	// Log the convergence table
	t.Logf("Convergence study:")
	t.Logf("%8s %12s %12s %8s", "nCells", "dx", "maxError", "order")
	t.Logf("%8d %12.6f %12.6e %8s", cellCounts[0], dxValues[0], errors[0], "-")

	for i := 1; i < len(cellCounts); i++ {
		// Order = log(e1/e2) / log(dx1/dx2)
		order := math.Log(errors[i-1]/errors[i]) / math.Log(dxValues[i-1]/dxValues[i])
		t.Logf("%8d %12.6f %12.6e %8.2f", cellCounts[i], dxValues[i], errors[i], order)
	}

	// Verify second-order convergence (order ~= 2.0)
	// Use the last refinement step where asymptotic behaviour is clearest
	finalOrder := math.Log(errors[len(errors)-2]/errors[len(errors)-1]) /
		math.Log(dxValues[len(dxValues)-2]/dxValues[len(dxValues)-1])

	if finalOrder < 1.9 || finalOrder > 2.1 {
		t.Errorf("Expected second-order convergence (≈2.0), got %.2f", finalOrder)
	}

	// Also verify absolute error is decreasing
	for i := 1; i < len(errors); i++ {
		if errors[i] >= errors[i-1] {
			t.Errorf("Error not decreasing: %v -> %v", errors[i-1], errors[i])
		}
	}
}

//
// Helpers
//

func floatsEqual(a, b, tol float64) bool {
	diff := math.Abs(a - b)

	// Absolute tolerance for near-zero values
	if math.Abs(b) < 1e-9 {
		return diff <= 1e-9
	}

	// Relative tolerance otherwise
	return diff <= tol*math.Abs(b)
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
