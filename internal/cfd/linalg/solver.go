package linalg

type SolverDefinition interface {
	Resolve(n int) Solver
}

type Solver interface {
	Solve(*System) []float32
}
