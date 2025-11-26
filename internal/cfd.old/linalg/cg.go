package linalg

// JACOBI PRECONDITIONED

type jacobiCG struct {
	maxIterations int
	tolerance     float32
	residual      []float32
	direction     []float32
	matd          []float32
	jacobi        []float32
}

func (cg *jacobiCG) Solve(sys *System, x []float32) []float32 {
	matrix := sys.A
	rhs := sys.B
	r := cg.residual
	d := cg.direction
	z := cg.jacobi
	Ad := cg.matd

	Ax := matrix.MatVec(x, r)
	for i, val := range Ax {
		r[i] = rhs[i] - val
		d[i] = 1 / matrix.GetDiagonal(i) * r[i]
	}

	var rDotr float32 = 0
	for i, val := range r {
		rDotr += val * d[i]
	}

	recomputeAxInterval := 50

	threshold := cg.tolerance * cg.tolerance * rDotr
	for iter := 0; iter < cg.maxIterations && rDotr > threshold; iter++ {
		Ad = matrix.MatVec(d, Ad)

		var dDotAd float32 = 0
		for i, val := range d {
			dDotAd += val * Ad[i]
		}

		alpha := rDotr / dDotAd

		for i, val := range x {
			x[i] = val + alpha*d[i]
		}

		if iter%recomputeAxInterval == 0 {
			Ax = matrix.MatVec(x, r)
			for i, val := range Ax {
				r[i] = rhs[i] - val
			}
		} else {
			for i, val := range r {
				r[i] = val - alpha*Ad[i]
			}
		}

		for i, val := range r {
			z[i] = val / matrix.GetDiagonal(i)
		}

		rDotrOld := rDotr
		rDotr = 0
		for i, val := range r {
			rDotr += val * z[i]
		}

		beta := rDotr / rDotrOld

		for i, val := range d {
			d[i] = z[i] + beta*val
		}
	}

	return x
}

type jacobiCGDefinition struct {
	maxIterations int
	tolerance     float32
}

func NewJacobiCG(maxIterations int, tolerance float32) SolverDefinition {
	return &jacobiCGDefinition{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (cg *jacobiCGDefinition) Resolve(n int) Solver {
	return &jacobiCG{
		maxIterations: cg.maxIterations,
		tolerance:     cg.tolerance,
		residual:      make([]float32, n),
		direction:     make([]float32, n),
		matd:          make([]float32, n),
		jacobi:        make([]float32, n),
	}
}

// NO PRECONDITIONER

type simpleCG struct {
	maxIterations int
	tolerance     float32
	residual      []float32
	direction     []float32
	matd          []float32
}

func (cg *simpleCG) Solve(sys *System, x []float32) []float32 {
	matrix := sys.A
	rhs := sys.B
	r := cg.residual
	d := cg.direction
	Ad := cg.matd

	Ax := matrix.MatVec(x, r)
	for i, val := range Ax {
		r[i] = rhs[i] - val
		d[i] = r[i]
	}

	var rDotr float32 = 0
	for _, val := range r {
		rDotr += val * val
	}

	recomputeAxInterval := 50

	threshold := cg.tolerance * cg.tolerance * rDotr
	for iter := 0; iter < cg.maxIterations && rDotr > threshold; iter++ {
		Ad = matrix.MatVec(d, Ad)

		var dDotAd float32 = 0
		for i, val := range d {
			dDotAd += val * Ad[i]
		}

		alpha := rDotr / dDotAd

		for i, val := range x {
			x[i] = val + alpha*d[i]
		}

		if iter%recomputeAxInterval == 0 {
			Ax = matrix.MatVec(x, r)
			for i, val := range Ax {
				r[i] = rhs[i] - val
			}
		} else {
			for i, val := range r {
				r[i] = val - alpha*Ad[i]
			}
		}

		rDotrOld := rDotr
		rDotr = 0
		for _, val := range r {
			rDotr += val * val
		}

		beta := rDotr / rDotrOld

		for i, val := range d {
			d[i] = r[i] + beta*val
		}
	}

	return x
}

type simpleCGDefinition struct {
	maxIterations int
	tolerance     float32
}

func NewSimpleCG(maxIterations int, tolerance float32) SolverDefinition {
	return &steepestDescentDefinition{
		maxIterations: maxIterations,
		tolerance:     tolerance,
	}
}

func (cg *simpleCGDefinition) Resolve(n int) Solver {
	return &simpleCG{
		maxIterations: cg.maxIterations,
		tolerance:     cg.tolerance,
		residual:      make([]float32, n),
		direction:     make([]float32, n),
		matd:          make([]float32, n),
	}
}
