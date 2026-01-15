package fvm

import (
	"jedn.dev/jnlcfd/geometry"
)

//
// Types
//

type LDUMatrix struct {
	diag  []float64
	lower []float64
	upper []float64
	conns []geometry.Connection
}

func NewLDUMatrix(mesh *geometry.Mesh) *LDUMatrix {
	nCells := len(mesh.Centroids)
	nConns := len(mesh.Connections)
	return &LDUMatrix{
		diag:  make([]float64, nCells),
		lower: make([]float64, nConns),
		upper: make([]float64, nConns),
		conns: mesh.Connections,
	}
}

type FVSystem struct {
	Matrix *LDUMatrix
	Rhs    []float64
}

func NewFVSystem(mesh *geometry.Mesh) *FVSystem {
	matrix := NewLDUMatrix(mesh)
	return &FVSystem{
		Matrix: matrix,
		Rhs:    make([]float64, len(mesh.Centroids)),
	}
}

//
// Simple solving functionality - cast to CSR for more sophisticated options
//

func (m *LDUMatrix) Zero() {
	for i := range m.diag {
		m.diag[i] = 0
	}
	for i := range m.lower {
		m.lower[i] = 0
		m.upper[i] = 0
	}
}

func (m *LDUMatrix) MatVec(x, y []float64) []float64 {
	// Diagonal contribution
	for i, diag := range m.diag {
		y[i] = diag * x[i]
	}

	// Off-diagonal contributions
	for f, conn := range m.conns {
		o := conn.Owner
		n := conn.Neighbour
		if n < 0 { // boundary connection
			continue
		}

		y[o] += m.upper[f] * x[n]
		y[n] += m.lower[f] * x[o]
	}

	return y
}

// Solve solves an FVSystem using the conjugate gradient method
func (sys *FVSystem) Solve(x []float64, tolerance float64, maxIters int) {
	nCells := len(sys.Rhs)

	A := sys.Matrix
	b := sys.Rhs

	r := make([]float64, nCells)
	d := make([]float64, nCells)
	Ad := make([]float64, nCells)

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

	threshold := tolerance * tolerance * rDotr
	for iter := 0; iter < maxIters && rDotr > threshold; iter++ {
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
}
