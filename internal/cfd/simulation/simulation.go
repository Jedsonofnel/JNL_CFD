package simulation

const (
	numIterations = 50
	tolerance     = 1e-6
)

type Simulation interface {
	Step(float32)
	GetTracerConcentration() []float32
}
