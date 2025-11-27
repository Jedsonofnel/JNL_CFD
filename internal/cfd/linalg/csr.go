package linalg

import (
	"strconv"
)

type CSR struct {
	Values    []float64
	Columns   []int
	RowStarts []int
}

func NewCSRFromArrays(values []float64, columns, rowStarts []int) *CSR {
	return &CSR{
		Values:    values,
		Columns:   columns,
		RowStarts: rowStarts,
	}
}

// DIMENSIONS

func (csr *CSR) Rows() int {
	return len(csr.RowStarts) - 1
}

// assuming it's a square matrix for my application - could find "max col"
// to make it more general
func (csr *CSR) Cols() int {
	return len(csr.RowStarts) - 1
}

// ELEMENT ACCESS

func (csr *CSR) Get(i, j int) float64 {
	startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.Columns[colIdx] == j {
			return csr.Values[colIdx]
		}
	}

	iStr := strconv.Itoa(i)
	jStr := strconv.Itoa(j)
	panic("Value at (" + iStr + ", " + jStr + ") is not present in this CSR matrix")
}

func (csr *CSR) GetDiagonal(i int) float64 {
	rowStart := csr.RowStarts[i]
	return csr.Values[rowStart]
}

// MATRIX PROPERTIES

func (csr *CSR) NonZeros() int {
	return len(csr.Values)
}

func (csr *CSR) IsZero(i, j int) bool {
	startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.Columns[colIdx] == j {
			return false
		}
	}

	return true
}

// ELEMENT MANIPULATION

func (csr *CSR) Set(i, j int, value float64) {
	startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.Columns[colIdx] == j {
			csr.Values[colIdx] = value
			return
		}
	}

	iStr := strconv.Itoa(i)
	jStr := strconv.Itoa(j)
	panic("Value at (" + iStr + ", " + jStr + ") is not present in this CSR matrix")
}

func (csr *CSR) SetDiagonal(i int, value float64) {
	rowStart := csr.RowStarts[i]
	csr.Values[rowStart] = value
}

func (csr *CSR) Add(i, j int, value float64) {
	startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.Columns[colIdx] == j {
			csr.Values[colIdx] += value
			return
		}
	}

	iStr := strconv.Itoa(i)
	jStr := strconv.Itoa(j)
	panic("Value at (" + iStr + ", " + jStr + ") is not present in this CSR matrix")
}

func (csr *CSR) AddDiagonal(i int, value float64) {
	rowStart := csr.RowStarts[i]
	csr.Values[rowStart] += value
}

func (csr *CSR) Subtract(i, j int, value float64) {
	startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.Columns[colIdx] == j {
			csr.Values[colIdx] -= value
			return
		}
	}

	iStr := strconv.Itoa(i)
	jStr := strconv.Itoa(j)
	panic("Value at (" + iStr + ", " + jStr + ") is not present in this CSR matrix")
}

// BULK OPERATIONS

func (csr *CSR) MatVec(x, y []float64) []float64 {
	for i := range csr.Rows() {
		y[i] = 0
		csr.ForEachInRow(i, func(j int, val float64) {
			y[i] += val * x[j]
		})
	}

	return y
}

func (csr *CSR) MatTVec(x, y []float64) []float64 {
	for i := range csr.Rows() {
		y[i] = 0
	}

	for j := range csr.Cols() {
		csr.ForEachInRow(j, func(i int, val float64) {
			y[i] += val * x[j]
		})
	}
	return y
}

func (csr *CSR) CopyFrom(other *CSR) {
	if csr.Rows() != other.Rows() || csr.Cols() != other.Cols() {
		panic("CopyFrom: matrix dimension mismatch")
	}

	// Copy row by row
	for i := 0; i < csr.Rows(); i++ {
		startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]
		for colIdx := startIdx; colIdx < endIdx; colIdx++ {
			j := csr.Columns[colIdx]
			csr.Values[colIdx] = other.Get(i, j)
		}
	}
}

func (csr *CSR) Wipe() {
	for i := range csr.Values {
		csr.Values[i] = 0.0
	}
}

func (csr *CSR) ForEachInRow(i int, fn func(j int, value float64)) {
	startIdx, endIdx := csr.RowStarts[i], csr.RowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		fn(csr.Columns[colIdx], csr.Values[colIdx])
	}
}
