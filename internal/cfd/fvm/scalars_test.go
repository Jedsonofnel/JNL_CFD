package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"testing"
)

func TestScalarAdvanceTime(t *testing.T) {
	tf := sample1x5TemperatureField()

	tf.AdvanceTime(0.016)

	var want float32 = 0.016
	if got := tf.dt; got != want {
		t.Errorf("dt error: got: %v, want: %v", got, want)
	}

	wantedInternalMatrix := [][]float32{
		{4, -4, 0, 0, 0},
		{-4, 8, -4, 0, 0},
		{0, -4, 8, -4, 0},
		{0, 0, -4, 8, -4},
		{0, 0, 0, -4, 4},
	}

	intMat := tf.sys.MatrixInternal

	for i, row := range wantedInternalMatrix {
		intMat.ForEachInRow(i, func(j int, val float32) {
			want := row[j]
			if got := val; got != want {
				t.Errorf("internal matrix error (%d, %d): got: %v, want: %v",
					i, j, got, want)
			}
		})
	}

	wantedBoundaryDiag := []float32{
		32, 32, 8,
		32, 32,
		32, 32,
		32, 32,
		32, 8, 32,
	}

	if got := tf.sys.BoundaryDiag; !floatSlicesEqual(got, wantedBoundaryDiag, 1e-6) {
		t.Errorf("boundary diag error: got: %v, want: %v", got, wantedBoundaryDiag)
	}
}

func TestScalarAssembleSystem(t *testing.T) {
	tf := sample1x5TemperatureField()
	tf.AdvanceTime(0.016)

	sys := tf.AssembleSystem()
	mat := sys.A

	wantedMatrix := [][]float32{
		{12, -4, 0, 0, 0},
		{-4, 8, -4, 0, 0},
		{0, -4, 8, -4, 0},
		{0, 0, -4, 8, -4},
		{0, 0, 0, -4, 12},
	}

	for i, row := range wantedMatrix {
		mat.ForEachInRow(i, func(j int, val float32) {
			want := row[j]
			if got := val; got != want {
				t.Errorf("matrix error (%d, %d): got %v, want %v",
					i, j, got, want)
			}
		})
	}

	wantedRHS := []float32{160, 0, 0, 0, 40}
	if got := sys.B; !floatSlicesEqual(got, wantedRHS, 1e-6) {
		t.Errorf("RHS error: got %v, want %v", got, wantedRHS)
	}
}

// helpers

func sample1x5TemperatureField() *ScalarPrognostic {
	sm := geometry.NewStructuredMesh(5, 1, 10, 1)
	mesh := sm.Resolve()

	tfd := NewScalarPrognosticDefinition("T", 0)
	tfd.SetBoundaryConditions(sm, map[string]ScalarBCDefinition{
		"northBorder": ScalarNeumann{},
		"eastBorder":  ScalarDirichlet{Value: 5.0},
		"southBorder": ScalarNeumann{},
		"westBorder":  ScalarDirichlet{Value: 20.0},
	})

	tfd.SetEquation(NewScalarLaplacian(tfd, 8))

	tf, _ := tfd.Resolve(mesh)
	return tf
}
