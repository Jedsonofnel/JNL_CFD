package linalg

type steepestDescent struct {
	maxIterations int
	tolerance     float64
	residual      []float64
	matr          []float64
}

func (sd *steepestDescent) Solve(sys *System, x []float64) []float64 {
	matrix := sys.A
	rhs := sys.B
	r := sd.residual
	Ar := sd.matr

	Ax := matrix.MatVec(x, r)
	for i, val := range Ax {
		r[i] = rhs[i] - val
	}

	var rDotr float64 = 0
	for _, val := range r {
		rDotr += val * val
	}

	recomputeAxInterval := 50

	threshold := sd.tolerance * sd.tolerance * rDotr
	for iter := 0; iter < sd.maxIterations && rDotr > threshold; iter++ {
		Ar = matrix.MatVec(r, Ar)

		var rDotAr float64 = 0
		for i, val := range r {
			rDotAr += val * Ar[i]
		}

		alpha := rDotr / rDotAr

		for i, val := range x {
			x[i] = val + alpha*r[i]
		}

		if iter%recomputeAxInterval == 0 {
			Ax = matrix.MatVec(x, r)
			for i, val := range Ax {
				r[i] = rhs[i] - val
			}
		} else {
			for i, val := range r {
				r[i] = val - alpha*Ar[i]
			}
		}

		rDotr = 0
		for _, val := range r {
			rDotr += val * val
		}
	}

	return x
}

type steepestDescentDefinition struct {
	maxIterations int
	tolerance     float64
}

func NewSteepestDescent(maxIterations int, tolerance float64) SolverDefinition {
	return &steepestDescentDefinition{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (sdd *steepestDescentDefinition) Resolve(n int) Solver {
	return &steepestDescent{
		maxIterations: sdd.maxIterations,
		tolerance:     sdd.tolerance,
		residual:      make([]float64, n),
		matr:          make([]float64, n),
	}
}
