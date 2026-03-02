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

	scratch [][]float64 // for solvers to use

	singularity uint8
}

func NewFVSystem(mesh *geometry.Mesh) *FVSystem {
	matrix := NewLDUMatrix(mesh)
	scratch := make([][]float64, 8) // 8 for BiCGSTAB
	for i := range scratch {
		scratch[i] = make([]float64, len(mesh.Centroids))
	}

	return &FVSystem{
		Matrix:  matrix,
		Rhs:     make([]float64, len(mesh.Centroids)),
		scratch: scratch,
	}
}

const (
	singularityUnchecked uint8 = iota
	singularityNonSingular
	singularityNeedsPin
)

//
// Simple solving functionality - cast to CSR for more sophisticated options
//

func (m *LDUMatrix) Zero() {
	clear(m.diag)
	clear(m.lower)
	clear(m.upper)
}

func (sys *FVSystem) Reset() {
	clear(sys.Rhs)
	sys.Matrix.Zero()

	for i := range sys.scratch {
		clear(sys.scratch[i])
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

// Solve solves an FVSystem using the conjugate gradient method with a jacobi
// preconditioner
func (sys *FVSystem) SolveCG(x []float64, tolerance float64, maxIters int) {
	sys.EnsureNonSingular()

	if maxIters <= 0 {
		maxIters = min(len(x), 1000)
	}

	A := sys.Matrix
	b := sys.Rhs

	r := sys.scratch[0]
	d := sys.scratch[1]
	Ad := sys.scratch[2]
	z := sys.scratch[3]

	Ax := A.MatVec(x, r)
	for i, val := range Ax {
		r[i] = b[i] - val
		d[i] = 1 / A.diag[i] * r[i]
	}

	rDotr := dot(r, d)

	recomputeAxInterval := 50

	threshold := tolerance * tolerance * rDotr
	for iter := 0; iter < maxIters && rDotr > threshold; iter++ {
		Ad = A.MatVec(d, Ad)

		dDotAd := dot(d, Ad)

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
			z[i] = val / A.diag[i]
		}

		rDotrOld := rDotr
		rDotr = dot(r, z)

		beta := rDotr / rDotrOld

		for i, val := range d {
			d[i] = z[i] + beta*val
		}
	}
}

func (sys *FVSystem) SolveBiCGSTAB(x []float64, tolerance float64, maxIters int) {
	sys.EnsureNonSingular()

	if maxIters <= 0 {
		maxIters = min(len(x), 1000)
	}

	A := sys.Matrix
	b := sys.Rhs
	n := len(b)

	// Scratch allocation
	r := sys.scratch[0]
	rHat := sys.scratch[1]
	p := sys.scratch[2]
	v := sys.scratch[3]
	s := sys.scratch[4]
	t := sys.scratch[5]
	y := sys.scratch[6]
	z := sys.scratch[7]

	// r_0 = b - Ax_0 (initial residual)
	A.MatVec(x, r)
	for i := range n {
		r[i] = b[i] - r[i]
	}

	// choose rHat_0 such that (r_0, rHat_0) != 0
	copy(rHat, r)

	rho := dot(rHat, r)

	// p_0 = r_0
	copy(p, r)

	// compute initial residual for convergence check
	thresholdSq := tolerance * tolerance * dot(r, r)

	for range maxIters {
		// y = K_2^-1 K_1^-1 p (K_2 = I, K_1 = diag for Jacobi, y = p / diag)
		for i := range n {
			y[i] = p[i] / A.diag[i]
		}

		// v = Ay
		A.MatVec(y, v)

		// alpha = rho_{i-1} / (rHat, v)
		rHatDotV := dot(rHat, v)
		if math.Abs(rHatDotV) < 1e-30 {
			break // breakdown
		}
		alpha := rho / rHatDotV

		// h = x + alpha.y (early candidate)
		// s = r - alpha.v
		for i := range n {
			x[i] = x[i] + alpha*y[i]
			s[i] = r[i] - alpha*v[i]
		}

		if dot(s, s) < thresholdSq {
			return // x already holds h
		}

		// z = K_2^-1.K_1^-1.s = s / diag
		for i := range n {
			z[i] = s[i] / A.diag[i]
		}

		// t = Az
		A.MatVec(z, t)

		// simplified omega calculation for Jacobi
		tDotS := dot(t, s)
		tDotT := dot(t, t)
		if math.Abs(tDotT) < 1e-30 {
			break // breakdown
		}
		omega := tDotS / tDotT

		// x_i = h + omega.z
		// r_i = s - omega.t
		for i := range n {
			x[i] = x[i] + omega*z[i]
			r[i] = s[i] - omega*t[i]
		}

		if dot(r, r) < thresholdSq {
			return
		}

		// rho_i = (rHat, r_i)
		rhoNew := dot(rHat, r)

		// beta = (rho_i / rho_{i-1}) * (alpha / omega)
		if math.Abs(rho) < 1e-30 || math.Abs(omega) < 1e-30 {
			break // breakdown
		}
		beta := (rhoNew / rho) * (alpha / omega)

		// p_i = r_i + beta.(p_{i-1} - omega.v)
		for i := range n {
			p[i] = r[i] + beta*(p[i]-omega*v[i])
		}

		rho = rhoNew
	}
}

func (sys *FVSystem) UnderRelax(fieldOld []float64, alpha float64) {
	for i := range sys.Matrix.diag {
		sys.Rhs[i] += ((1 - alpha) / alpha) * sys.Matrix.diag[i] * fieldOld[i]
		sys.Matrix.diag[i] /= alpha
	}
}

//
// Linear algebra helpers
//

func dot(a, b []float64) float64 {
	sum := 0.0
	for i, v := range a {
		sum += v * b[i]
	}
	return sum
}

//
// Singularity detection
//

// EnsureNonSingular detects singular matrices (all-Neumann Laplacians etc.)
// and pins cell 0 to remove the null space. Caches the result so subsequent
// calls after Reset() re-pin without rechecking.
func (sys *FVSystem) EnsureNonSingular() {
	switch sys.singularity {
	case singularityNonSingular:
		return
	case singularityNeedsPin:
		sys.PinCell(0, 0.0)
		return
	}

	if sys.maxRowSumRatio() < 1e-10 {
		sys.singularity = singularityNeedsPin
		sys.PinCell(0, 0.0)
	} else {
		sys.singularity = singularityNonSingular
	}
}

// maxRowSumRatio returns max(|row_sum|) / max(|diag|).
// Near-zero means every row sums to ~0 → singular.
func (sys *FVSystem) maxRowSumRatio() float64 {
	m := sys.Matrix
	n := len(m.diag)

	rowSums := make([]float64, n)
	copy(rowSums, m.diag)

	for f, conn := range m.conns {
		if conn.Neighbour < 0 {
			continue
		}
		rowSums[conn.Owner] += m.upper[f]
		rowSums[conn.Neighbour] += m.lower[f]
	}

	maxSum, maxDiag := 0.0, 0.0
	for i := range n {
		if v := math.Abs(rowSums[i]); v > maxSum {
			maxSum = v
		}
		if v := math.Abs(m.diag[i]); v > maxDiag {
			maxDiag = v
		}
	}

	if maxDiag < 1e-30 {
		return 0
	}
	return maxSum / maxDiag
}

func (sys *FVSystem) ResetSingularityCache() {
	sys.singularity = singularityUnchecked
}

// PinCell zeroes row/column for cellIdx, sets diag=1, rhs=value.
func (sys *FVSystem) PinCell(cellIdx int, value float64) {
	for k, conn := range sys.Matrix.conns {
		if conn.Owner == int32(cellIdx) {
			sys.Matrix.lower[k] = 0
		}
		if conn.Neighbour == int32(cellIdx) {
			sys.Matrix.upper[k] = 0
		}
	}
	sys.Matrix.diag[cellIdx] = 1.0
	sys.Rhs[cellIdx] = value
}

// PinCells pins every cell in the list to value.
func (sys *FVSystem) PinCells(cells []int, value float64) {
	pinned := make(map[int32]bool, len(cells))
	for _, idx := range cells {
		pinned[int32(idx)] = true
	}
	for k, conn := range sys.Matrix.conns {
		if pinned[conn.Owner] {
			sys.Matrix.lower[k] = 0
		}
		if pinned[conn.Neighbour] {
			sys.Matrix.upper[k] = 0
		}
	}
	for _, idx := range cells {
		sys.Matrix.diag[idx] = 1.0
		sys.Rhs[idx] = value
	}
}

// CopyDiag copies the current diagonal into dst.
func (sys *FVSystem) CopyDiag(dst []float64) {
	copy(dst, sys.Matrix.diag)
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
			if conn.Neighbour < 0 {
				continue
			}
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
