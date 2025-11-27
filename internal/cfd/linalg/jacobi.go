package linalg

type Jacobi struct {
	maxIterations int
	tolerance     float64
}

func NewJacobi(maxIterations int, tolerance float64) *Jacobi {
	return &Jacobi{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (j *Jacobi) Solve(A *CSR, b, x []float64) error {
	n := len(b)
	xNew := make([]float64, n) // this is always going to be rubbish

	for iter := 0; iter < j.maxIterations; iter++ {
		for i := range n {
			var sum float64 = 0.0

			for k := range n {
				if i != k {
					sum += A.Get(i, k) * x[k]
				}
			}
			xNew[i] = (b[i] - sum) / A.Get(i, i)
		}

		// Copy xNew to x
		copy(x, xNew)
	}

	return nil
}
