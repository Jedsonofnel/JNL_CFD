package linalg

type Jacobi struct {
	maxIterations int
	tolerance     float64
}

func (j *Jacobi) Solve(sys *System, x []float64) []float64 {
	matrix := sys.A
	rhs := sys.B

	n := len(rhs)
	xNew := make([]float64, n) // this is always going to be rubbish

	for iter := 0; iter < j.maxIterations; iter++ {
		for i := range n {
			var sum float64 = 0.0

			for k := range n {
				if i != k {
					sum += matrix.Get(i, k) * x[k]
				}
			}
			xNew[i] = (rhs[i] - sum) / matrix.Get(i, i)
		}

		// Copy xNew to x
		copy(x, xNew)
	}

	return x
}

type JacobiDefinition struct {
	maxIterations int
	tolerance     float64
}

func NewJacobi(maxIterations int, tolerance float64) SolverDefinition {
	return &JacobiDefinition{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (jd *JacobiDefinition) Resolve(n int) Solver {
	return &Jacobi{
		maxIterations: jd.maxIterations,
		tolerance:     jd.tolerance,
	}
}
