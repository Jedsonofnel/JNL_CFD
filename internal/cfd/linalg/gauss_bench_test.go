package linalg

import (
	"testing"
)

func BenchmarkMatrixImplementations(b *testing.B) {
	gauss := NewGaussSeidel(1, 1e-8)
	x := make([]float32, 1000)
	for i := range x {
		x[i] = 1.0
	}

	b.Run("Dense", func(b *testing.B) {
		matrix := NewDenseMatrix(1000, 1000)
		PopulateMatrixWithTestSystem(matrix)
		sys := System{A: matrix, B: x}

		b.ResetTimer()
		for b.Loop() {
			sol := gauss.Solve(sys)
			_ = sol
		}
	})
	b.Run("CSR", func(b *testing.B) {
		matrix := NewTestCSR(1000)
		PopulateMatrixWithTestSystem(matrix)
		sys := System{A: matrix, B: x}

		b.ResetTimer()
		for b.Loop() {
			sol := gauss.Solve(sys)
			_ = sol
		}
	})
}

func NewTestCSR(nCells int) Matrix {
	neighbourStarts := make([]int, nCells+1)
	neighbourIndices := make([]int, nCells*4)

	for i := range nCells {
		neighbourStarts[i] = i * 4
		neighbourIndices[i*4] = (i + 1) % 1000
		neighbourIndices[i*4+1] = (i + 2) % 1000
		neighbourIndices[i*4+2] = (i + 3) % 1000
		neighbourIndices[i*4+3] = (i + 4) % 1000
	}
	neighbourStarts[nCells] = nCells * 4

	return NewCSRMatrixFromConnectivity(neighbourStarts, neighbourIndices)
}

func PopulateMatrixWithTestSystem(matrix Matrix) {
	for i := range matrix.Rows() {
		matrix.Set(i, i, 4.0)

		neighboursAssigned := 0
		matrix.ForEachInRow(i, func(j int, _ float32) {
			if i != j && neighboursAssigned < 4 {
				matrix.Set(i, j, -1.0)
				neighboursAssigned++
			}
		})
	}
}
