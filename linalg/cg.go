package linalg

// JACOBI PRECONDITIONED

type JacobiCG struct {
	maxIterations int
	tolerance     float64
	residual      []float64
	direction     []float64
	matd          []float64
	jacobi        []float64
}

func NewJacobiCG(n, maxIterations int, tolerance float64) *JacobiCG {
	return &JacobiCG{
		maxIterations: maxIterations,
		tolerance:     tolerance,
		residual:      make([]float64, n),
		direction:     make([]float64, n),
		matd:          make([]float64, n),
		jacobi:        make([]float64, n),
	}
}

func (cg *JacobiCG) Solve(A *CSR, b, x []float64) error {
	r := cg.residual
	d := cg.direction
	z := cg.jacobi
	Ad := cg.matd

	Ax := A.MatVec(x, r)
	for i, val := range Ax {
		r[i] = b[i] - val
		d[i] = 1 / A.GetDiagonal(i) * r[i]
	}

	var rDotr float64 = 0
	for i, val := range r {
		rDotr += val * d[i]
	}

	recomputeAxInterval := 50

	threshold := cg.tolerance * cg.tolerance * rDotr
	for iter := 0; iter < cg.maxIterations && rDotr > threshold; iter++ {
		Ad = A.MatVec(d, Ad)

		var dDotAd float64 = 0
		for i, val := range d {
			dDotAd += val * Ad[i]
		}

		alpha := rDotr / dDotAd

		for i, val := range x {
			x[i] = val + alpha*d[i]
		}

		if iter%recomputeAxInterval == 0 {
			Ax = A.MatVec(x, r)
			for i, val := range Ax {
				r[i] = b[i] - val
			}
		} else {
			for i, val := range r {
				r[i] = val - alpha*Ad[i]
			}
		}

		for i, val := range r {
			z[i] = val / A.GetDiagonal(i)
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

	return nil
}

// NO PRECONDITIONER

type SimpleCG struct {
	maxIterations int
	tolerance     float64
	residual      []float64
	direction     []float64
	matd          []float64
}

func NewSimpleCG(n, maxIterations int, tolerance float64) *SimpleCG {
	return &SimpleCG{
		maxIterations: maxIterations,
		tolerance:     tolerance,
		residual:      make([]float64, n),
		direction:     make([]float64, n),
		matd:          make([]float64, n),
	}
}

func (cg *SimpleCG) Solve(A *CSR, b, x []float64) error {
	r := cg.residual
	d := cg.direction
	Ad := cg.matd

	Ax := A.MatVec(x, r)
	for i, val := range Ax {
		r[i] = b[i] - val
		d[i] = r[i]
	}

	var rDotr float64 = 0
	for _, val := range r {
		rDotr += val * val
	}

	recomputeAxInterval := 50

	threshold := cg.tolerance * cg.tolerance * rDotr
	for iter := 0; iter < cg.maxIterations && rDotr > threshold; iter++ {
		Ad = A.MatVec(d, Ad)

		var dDotAd float64 = 0
		for i, val := range d {
			dDotAd += val * Ad[i]
		}

		alpha := rDotr / dDotAd

		for i, val := range x {
			x[i] = val + alpha*d[i]
		}

		if iter%recomputeAxInterval == 0 {
			Ax = A.MatVec(x, r)
			for i, val := range Ax {
				r[i] = b[i] - val
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

	return nil
}
