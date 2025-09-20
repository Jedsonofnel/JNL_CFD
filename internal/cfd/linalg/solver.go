package linalg

type SolverDefinition interface {
	Resolve(n int) Solver
}

type Solver interface {
	Solve(sys *System, x []float32) []float32
}
