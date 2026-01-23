package fvm

import (
	"math"

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

//
// System diagnostic functions
//

// DiagonalDominanceRatio gives the min across every cell
func (sys *FVSystem) DiagonalDominanceRatio() float64 {
	nCells := len(sys.Matrix.diag)
	offDiagSums := make([]float64, nCells)

	for i, conn := range sys.Matrix.conns {
		if conn.Neighbour < 0 {
			continue // skip BC
		}

		owner := int(conn.Owner)
		offDiagSums[owner] += math.Abs(sys.Matrix.lower[i])
		neighbour := int(conn.Neighbour)
		offDiagSums[neighbour] += math.Abs(sys.Matrix.upper[i])
	}

	minRatio := math.Inf(1)
	for i := range nCells {
		if offDiagSums[i] > 1e-14 {
			ratio := math.Abs(sys.Matrix.diag[i]) / offDiagSums[i]
			minRatio = math.Min(minRatio, ratio)
		}
	}
	return minRatio
}

// Check symmetry (for diffusion, lower should equal upper)
func (sys *FVSystem) MaxAsymmetry() float64 {
	maxAsym := 0.0
	for i, conn := range sys.Matrix.conns {
		// Only check internal faces (neighbour >= 0)
		if conn.Neighbour >= 0 {
			asym := math.Abs(sys.Matrix.lower[i] - sys.Matrix.upper[i])
			maxAsym = math.Max(maxAsym, asym)
		}
	}
	return maxAsym // should be ~0 for symmetric operators
}

// Max row sum (check conservation)
func (sys *FVSystem) MaxRowSum() float64 {
	nCells := len(sys.Matrix.diag)
	maxSum := 0.0

	for i := range nCells {
		rowSum := sys.Matrix.diag[i]

		for connIdx, conn := range sys.Matrix.conns {
			if conn.Owner == int32(i) {
				rowSum += sys.Matrix.lower[connIdx]
			}
			if conn.Neighbour == int32(i) {
				rowSum += sys.Matrix.upper[connIdx]
			}
		}

		maxSum = math.Max(maxSum, math.Abs(rowSum))
	}
	return maxSum
}

// Min/max diagonal
func (sys *FVSystem) MinDiagonal() float64 {
	minD := math.Inf(1)
	for _, d := range sys.Matrix.diag {
		minD = math.Min(minD, d)
	}
	return minD // should be > 0
}

func (sys *FVSystem) MaxDiagonal() float64 {
	maxD := math.Inf(-1)
	for _, d := range sys.Matrix.diag {
		maxD = math.Max(maxD, d)
	}
	return maxD
}

func (sys *FVSystem) DiagonalConditionNumber() float64 {
	minD := sys.MinDiagonal()
	maxD := sys.MaxDiagonal()
	if math.Abs(minD) < 1e-14 {
		return math.Inf(1)
	}
	return math.Abs(maxD / minD)
}

// Check all diagonals positive
func (sys *FVSystem) AllDiagonalsPositive() bool {
	for _, d := range sys.Matrix.diag {
		if d <= 0 {
			return false
		}
	}
	return true
}

// Residual: r = Ax - b
func (sys *FVSystem) ResidualNorm(x []float64) float64 {
	nCells := len(sys.Matrix.diag)
	residual := 0.0

	for i := range nCells {
		// Start with diagonal contribution
		ax := sys.Matrix.diag[i] * x[i]

		// Add off-diagonal contributions
		for connIdx, conn := range sys.Matrix.conns {
			if conn.Owner == int32(i) && conn.Neighbour >= 0 {
				ax += sys.Matrix.lower[connIdx] * x[conn.Neighbour]
			}
			if conn.Neighbour == int32(i) {
				ax += sys.Matrix.upper[connIdx] * x[conn.Owner]
			}
		}

		r := ax - sys.Rhs[i]
		residual += r * r
	}
	return math.Sqrt(residual)
}

func (sys *FVSystem) ResidualInfNorm(x []float64) float64 {
	nCells := len(sys.Matrix.diag)
	maxRes := 0.0

	for i := range nCells {
		ax := sys.Matrix.diag[i] * x[i]

		for connIdx, conn := range sys.Matrix.conns {
			if conn.Owner == int32(i) && conn.Neighbour >= 0 {
				ax += sys.Matrix.lower[connIdx] * x[conn.Neighbour]
			}
			if conn.Neighbour == int32(i) {
				ax += sys.Matrix.upper[connIdx] * x[conn.Owner]
			}
		}

		r := math.Abs(ax - sys.Rhs[i])
		maxRes = math.Max(maxRes, r)
	}
	return maxRes
}

func (sys *FVSystem) RHSNorm() float64 {
	sum := 0.0
	for _, b := range sys.Rhs {
		sum += b * b
	}
	return math.Sqrt(sum)
}

// Sparsity
func (sys *FVSystem) NonZeroCount() int {
	count := len(sys.Matrix.diag) // all diagonals

	for i, conn := range sys.Matrix.conns {
		if math.Abs(sys.Matrix.lower[i]) > 1e-14 {
			count++
		}
		if conn.Neighbour >= 0 && math.Abs(sys.Matrix.upper[i]) > 1e-14 {
			count++
		}
	}
	return count
}

// For cell i, get number of connections (degree)
func (sys *FVSystem) CellDegree(cellIdx int) int {
	degree := 0
	for _, conn := range sys.Matrix.conns {
		if conn.Owner == int32(cellIdx) || conn.Neighbour == int32(cellIdx) {
			degree++
		}
	}
	return degree
}

// Max degree (useful for mesh quality check)
func (sys *FVSystem) MaxCellDegree() int {
	nCells := len(sys.Matrix.diag)
	maxDeg := 0
	for i := range nCells {
		deg := sys.CellDegree(i)
		maxDeg = max(deg, maxDeg)
	}
	return maxDeg
}
