package field

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"math"
	"slices"
	"testing"
)

// LAPLACIAN

func TestScalarLaplacianResolve(t *testing.T) {
	mesh := sample1x5StructuredMesh()

	laplacianDef := NewScalarLaplacian(nil, 8)
	laplacian := laplacianDef.Resolve(mesh)

	wantedOpType := laplacianType
	if got := laplacian.opType; got != wantedOpType {
		t.Errorf("opType error: got: %v, want: %v", got, wantedOpType)
	}

	var wantedCoeff float32 = 8
	if got := laplacian.coeff; got != wantedCoeff {
		t.Errorf("coeff error: got: %v, want: %v", got, wantedCoeff)
	}

	var wantedCoupledScalars []scalar = []scalar{}
	if got := len(laplacian.coupledScalars); got != len(wantedCoupledScalars) {
		t.Errorf("coupledScalars error: got: %v, want: %v", got, len(wantedCoupledScalars))
	}

	wantedPrecalcs := []float32{
		16, 8, 16, 16,
		16, 8, 16, 8,
		16, 8, 16, 8,
		16, 8, 16, 8,
		16, 16, 16, 8,
	}
	if got := laplacian.precalcs; !floatSlicesEqual(got, wantedPrecalcs, 1e-6) {
		t.Errorf("precalc error: got: %v, want %v", got, wantedPrecalcs)
	}
}

func TestScalarLaplacianApplyFluxes(t *testing.T) {
	mesh := sample1x5StructuredMesh()
	laplacianDef := NewScalarLaplacian(nil, 8)
	laplacian := laplacianDef.Resolve(mesh)

	sys := newSystemAssemblyContext(mesh.NumCells(),
		mesh.NumBoundaries(), mesh.FaceStarts, mesh.NeighbourIndices)

	applyFluxes(laplacian, mesh, sys)

	// test diagonals
	mat := sys.MatrixInternal
	wantedDiags := []float32{8, 16, 16, 16, 8}
	for i := range mesh.NumCells() {
		if got := mat.GetDiagonal(i); got != wantedDiags[i] {
			t.Errorf("Diag error: got %v, want %v", got, wantedDiags[i])
		}
	}

	wantedOffDiags := []struct {
		i, j  int
		value float32
	}{
		{0, 1, -8},
		{1, 0, -8},
		{1, 2, -8},
		{2, 1, -8},
		{2, 3, -8},
		{3, 2, -8},
		{3, 4, -8},
		{4, 3, -8},
	}

	for _, offDiag := range wantedOffDiags {
		want := offDiag.value
		if got := mat.Get(offDiag.i, offDiag.j); got != want {
			t.Errorf("Off diag error: got %v, want %v", got, want)
		}
	}

	// test boundaries
	wantedBoundDiag := []float32{
		16, 16, 16,
		16, 16,
		16, 16,
		16, 16,
		16, 16, 16,
	}

	if got := sys.BoundaryDiag; !floatSlicesEqual(got, wantedBoundDiag, 1e-6) {
		t.Errorf("boundary daig errors: got %v, want %v", got, wantedBoundDiag)
	}

	wantedBoundOffDiag := []float32{
		16, 16, 16,
		16, 16,
		16, 16,
		16, 16,
		16, 16, 16,
	}

	if got := sys.BoundaryOffDiag; !floatSlicesEqual(got, wantedBoundOffDiag, 1e-6) {
		t.Errorf("boundary off-diag errors: got %v, want %v", got, wantedBoundOffDiag)
	}
}

// helpers

func sample1x5StructuredMesh() *geometry.Mesh {
	sm := geometry.NewStructuredMesh(5, 1, 5, 1)
	return sm.Resolve()
}

func floatSlicesEqual(got, want []float32, tolerance float32) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if math.Abs(float64(got[i]-want[i])) > float64(tolerance) {
			return false
		}
	}

	return true
}

func intSlicesEqual(got, want []int) bool {
	return slices.Equal(got, want)
}
