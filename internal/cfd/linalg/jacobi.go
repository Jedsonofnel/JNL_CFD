package linalg

type Jacobi struct {
	maxIterations int
	tolerance     float32
}

func NewJacobi(maxIterations int, tolerance float32) Solver {
	return &Jacobi{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (j *Jacobi) Solve(sys System) []float32 {
	matrix := sys.A
	rhs := sys.B

	n := len(rhs)
	x := make([]float32, n)
	xNew := make([]float32, n)

	for iter := 0; iter < j.maxIterations; iter++ {
		for i := range n {
			var sum float32 = 0.0

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
