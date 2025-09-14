package linalg

import (
	"fmt"
	"sort"
)

type CSR struct {
	values    []float32
	columns   []int
	rowStarts []int
}

func NewCSRMatrixFromConnectivity(neighbourStarts, neighbourIndices []int) Matrix {
	nCells := len(neighbourStarts) - 1
	rowStarts := make([]int, nCells+1)

	totalValidNeighbours := 0
	for i := range nCells {
		startIdx, endIdx := neighbourStarts[i], neighbourStarts[i+1]
		for j := startIdx; j < endIdx; j++ {
			if neighbourIndices[j] >= 0 {
				totalValidNeighbours++
			}
		}
	}
	columns := make([]int, nCells+totalValidNeighbours) // total number of elements

	valuesAccountedFor := 0
	for i := 0; i < len(neighbourStarts)-1; i++ {
		rowStarts[i] = valuesAccountedFor
		startIdx, endIdx := neighbourStarts[i], neighbourStarts[i+1]

		// Collect valid neighbours (excluding boundaries and diagonal)
		offDiagonalColumns := make([]int, 0, endIdx-startIdx)
		for j := startIdx; j < endIdx; j++ {
			if neighbourIndices[j] >= 0 && neighbourIndices[j] != i {
				offDiagonalColumns = append(offDiagonalColumns, neighbourIndices[j])
			}
		}

		sort.Ints(offDiagonalColumns) // sort the columns for faster fetching later

		columns[valuesAccountedFor] = i
		copy(columns[valuesAccountedFor+1:valuesAccountedFor+1+len(offDiagonalColumns)], offDiagonalColumns)
		valuesAccountedFor += 1 + len(offDiagonalColumns)
	}

	rowStarts[nCells] = valuesAccountedFor // add the terminator
	return &CSR{
		values:    make([]float32, valuesAccountedFor),
		columns:   columns,
		rowStarts: rowStarts,
	}
}

// DIMENSIONS

func (csr *CSR) Rows() int {
	return len(csr.rowStarts) - 1
}

// assuming it's a square matrix for my application - could find "max col"
// to make it more general
func (csr *CSR) Cols() int {
	return len(csr.rowStarts) - 1
}

// ELEMENT ACCESS

func (csr *CSR) Get(i, j int) float32 {
	startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.columns[colIdx] == j {
			return csr.values[colIdx]
		}
	}

	panic(fmt.Sprintf("Value at (%d, %d) is not present in this CSR matrix", i, j))
}

func (csr *CSR) GetDiagonal(i int) float32 {
	rowStart := csr.rowStarts[i]
	return csr.values[rowStart]
}

// MATRIX PROPERTIES

func (csr *CSR) NonZeros() int {
	return len(csr.values)
}

func (csr *CSR) IsZero(i, j int) bool {
	startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.columns[colIdx] == j {
			return false
		}
	}

	return true
}

// ELEMENT MANIPULATION

func (csr *CSR) Set(i, j int, value float32) {
	startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.columns[colIdx] == j {
			csr.values[colIdx] = value
			return
		}
	}

	panic(fmt.Sprintf("Value at (%d, %d) is not present in this CSR matrix", i, j))
}

func (csr *CSR) SetDiagonal(i int, value float32) {
	rowStart := csr.rowStarts[i]
	csr.values[rowStart] = value
}

func (csr *CSR) Add(i, j int, value float32) {
	startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.columns[colIdx] == j {
			csr.values[colIdx] += value
			return
		}
	}

	panic(fmt.Sprintf("Value at (%d, %d) is not present in this CSR matrix", i, j))
}

func (csr *CSR) AddDiagonal(i int, value float32) {
	rowStart := csr.rowStarts[i]
	csr.values[rowStart] += value
}

func (csr *CSR) Subtract(i, j int, value float32) {
	startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		if csr.columns[colIdx] == j {
			csr.values[colIdx] -= value
			return
		}
	}

	panic(fmt.Sprintf("Value at (%d, %d) is not present in this CSR matrix", i, j))
}

// BULK OPERATIONS

// TODO: implement this
func (csr *CSR) MatVec(x []float32) []float32 {
	return make([]float32, 3)
}

func (csr *CSR) CopyFrom(other Matrix) {
	if csr.Rows() != other.Rows() || csr.Cols() != other.Cols() {
		panic("CopyFrom: matrix dimension mismatch")
	}

	// Copy row by row
	for i := 0; i < csr.Rows(); i++ {
		startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]
		for colIdx := startIdx; colIdx < endIdx; colIdx++ {
			j := csr.columns[colIdx]
			csr.values[colIdx] = other.Get(i, j)
		}
	}
}

func (csr *CSR) Wipe() {
	for i := range csr.values {
		csr.values[i] = 0.0
	}
}

func (csr *CSR) ForEachInRow(i int, fn func(j int, value float32)) {
	startIdx, endIdx := csr.rowStarts[i], csr.rowStarts[i+1]

	for colIdx := startIdx; colIdx < endIdx; colIdx++ {
		fn(csr.columns[colIdx], csr.values[colIdx])
	}
}
