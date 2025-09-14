package linalg

type Solver interface {
	Solve(System) []float32
}
