package linalg

type GaussSeidel struct {
	maxIterations int
	tolerance     float64
}

func NewGaussSeidel(maxIterations int, tolerance float64) *GaussSeidel {
	return &GaussSeidel{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (gs *GaussSeidel) Solve(A *CSR, b, x []float64) error {
	for iter := 0; iter < gs.maxIterations; iter++ {
		// Update solution
		for i := range x {
			var sum float64 = 0.0
			A.ForEachInRow(i, func(col int, val float64) {
				if col != i {
					sum += val * x[col]
				}
			})
			x[i] = (b[i] - sum) / A.GetDiagonal(i)
		}

		// Calculate true residual ||Ax - b||
		var residual float64 = 0.0
		for i := range x {
			var axRow float64 = 0.0
			A.ForEachInRow(i, func(col int, val float64) {
				axRow += val * x[col]
			})
			diff := axRow - b[i]
			residual += diff * diff
		}

		if residual < gs.tolerance {
			break
		}
	}

	return nil
}
