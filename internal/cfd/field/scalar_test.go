package field

import (
	"github.com/Jedsonofnel/cfd-but-wasm/linalg"
	"testing"
)

func TestScalarFieldAssembly1DHeatDiffusion(t *testing.T) {

}

func assertMatrixSymmetryForDiffusion(t *testing.T, matrix linalg.Matrix) {
	// Diffusion matrix should be symmetric in structure (ignoring time derivative)
	for i := 0; i < matrix.Rows(); i++ {
		for j := 0; j < matrix.Cols(); j++ {
			if (matrix.Get(i, j) != 0) != (matrix.Get(j, i) != 0) {
				t.Errorf("Matrix structure not symmetric at (%d,%d)", i, j)
			}
		}
	}
}

func assertPositiveDiagonal(t *testing.T, matrix linalg.Matrix, nCells int) {
	for i := range nCells {
		if got := matrix.Get(i, i); got <= 0 {
			t.Errorf("Diagonal[%d] = %f, want > 0", i, got)
		}
	}
}
