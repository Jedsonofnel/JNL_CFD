package linalg

type Solver interface {
	Solve(A *CSR, b, x []float64) error
}
