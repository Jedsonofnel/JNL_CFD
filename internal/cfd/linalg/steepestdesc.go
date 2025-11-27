package linalg

type SteepestDescent struct {
	maxIterations int
	tolerance     float64
	residual      []float64
	matr          []float64
}

func NewSteepestDescent(n, maxIterations int, tolerance float64) *SteepestDescent {
	return &SteepestDescent{
		maxIterations: maxIterations,
		tolerance:     tolerance,
		residual:      make([]float64, n),
		matr:          make([]float64, n),
	}
}

func (sd *SteepestDescent) Solve(A *CSR, b, x []float64) error {
	r := sd.residual
	Ar := sd.matr

	Ax := A.MatVec(x, r)
	for i, val := range Ax {
		r[i] = b[i] - val
	}

	var rDotr float64 = 0
	for _, val := range r {
		rDotr += val * val
	}

	recomputeAxInterval := 50

	threshold := sd.tolerance * sd.tolerance * rDotr
	for iter := 0; iter < sd.maxIterations && rDotr > threshold; iter++ {
		Ar = A.MatVec(r, Ar)

		var rDotAr float64 = 0
		for i, val := range r {
			rDotAr += val * Ar[i]
		}

		alpha := rDotr / rDotAr

		for i, val := range x {
			x[i] = val + alpha*r[i]
		}

		if iter%recomputeAxInterval == 0 {
			Ax = A.MatVec(x, r)
			for i, val := range Ax {
				r[i] = b[i] - val
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

	return nil
}
