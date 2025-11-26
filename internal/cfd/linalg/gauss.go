package linalg

type GaussSeidel struct {
	maxIterations int
	tolerance     float64
}

func (gs *GaussSeidel) Solve(sys *System, x []float64) []float64 {
	matrix := sys.A
	rhs := sys.B

	for iter := 0; iter < gs.maxIterations; iter++ {
		// Update solution
		for i := range x {
			var sum float64 = 0.0
			matrix.ForEachInRow(i, func(col int, val float64) {
				if col != i {
					sum += val * x[col]
				}
			})
			x[i] = (rhs[i] - sum) / matrix.GetDiagonal(i)
		}

		// Calculate true residual ||Ax - b||
		var residual float64 = 0.0
		for i := range x {
			var axRow float64 = 0.0
			matrix.ForEachInRow(i, func(col int, val float64) {
				axRow += val * x[col]
			})
			diff := axRow - rhs[i]
			residual += diff * diff
		}

		if residual < gs.tolerance {
			break
		}
	}

	return x
}

type GaussSeidelDefinition struct {
	maxIterations int
	tolerance     float64
}

func NewGaussSeidel(maxIterations int, tolerance float64) SolverDefinition {
	return &GaussSeidelDefinition{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (gsd *GaussSeidelDefinition) Resolve(n int) Solver {
	return &GaussSeidel{
		maxIterations: gsd.maxIterations,
		tolerance:     gsd.tolerance,
	}
}
