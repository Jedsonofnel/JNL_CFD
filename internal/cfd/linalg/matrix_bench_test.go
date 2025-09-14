package linalg

import "testing"

func BenchmarkMatVec(b *testing.B) {
	b.Run("Dense", func(b *testing.B) {
		matrix := NewDenseMatrix(1000, 1000) // setup your dense matrix
		x := make([]float32, 1000)

		b.ResetTimer()
		for b.Loop() {
			y := matrix.MatVec(x)
			_ = y
		}

	})
	b.Run("CSR", func(b *testing.B) {
		// Create fake connectivity: each cell has 4 neighbors
		neighbourStarts := make([]int, 1001)  // 1000 cells + terminator
		neighbourIndices := make([]int, 4000) // 1000 cells * 4 neighbors each

		for i := range 1000 {
			neighbourStarts[i] = i * 4
			neighbourIndices[i*4] = (i + 1) % 1000
			neighbourIndices[i*4+1] = (i + 2) % 1000
			neighbourIndices[i*4+2] = (i + 3) % 1000
			neighbourIndices[i*4+3] = (i + 4) % 1000
		}
		neighbourStarts[1000] = 4000 // terminator

		matrix := NewCSRMatrixFromConnectivity(neighbourStarts, neighbourIndices)
		x := make([]float32, 1000)

		b.ResetTimer()
		for b.Loop() {
			y := matrix.MatVec(x)
			_ = y
		}
	})
}
