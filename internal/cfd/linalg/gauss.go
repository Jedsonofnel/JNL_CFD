package linalg

import (
	"fmt"
)

const DEBUG = false

type GaussSeidel struct {
	maxIterations int
	tolerance     float32
}

func NewGaussSeidel(maxIterations int, tolerance float32) Solver {
	return &GaussSeidel{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (gs *GaussSeidel) Solve(sys *System) []float32 {
	matrix := sys.A
	rhs := sys.B

	n := len(rhs)
	x := make([]float32, n)

	for i := range x {
		x[i] = 0.0
	}

	for iter := 0; iter < gs.maxIterations; iter++ {
		// Update solution
		for i := range n {
			var sum float32 = 0.0
			matrix.ForEachInRow(i, func(col int, val float32) {
				if col != i {
					sum += val * x[col]
				}
			})
			x[i] = (rhs[i] - sum) / matrix.GetDiagonal(i)
		}

		// Calculate true residual ||Ax - b||
		var residual float32 = 0.0
		for i := range n {
			var axRow float32 = 0.0
			matrix.ForEachInRow(i, func(col int, val float32) {
				axRow += val * x[col]
			})
			diff := axRow - rhs[i]
			residual += diff * diff
		}

		if residual < gs.tolerance*gs.tolerance {
			if DEBUG {
				fmt.Printf("Gauss-Seidel converged after %d iterations\n", iter)
			}
			break
		}

		if iter%10 == 0 {
			if DEBUG {
				fmt.Printf("Iteration %d, residual: %.6f\n", iter, residual)
			}
		}
	}

	return x
}
