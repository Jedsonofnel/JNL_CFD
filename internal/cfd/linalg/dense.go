package linalg

import (
	"fmt"
	"strings"
)

type DenseMatrix struct {
	data   []float32
	nX, nY int
}

func NewDenseMatrix(nX, nY int) Matrix {
	return &DenseMatrix{
		nX:   nX,
		nY:   nY,
		data: make([]float32, nX*nY),
	}
}

func (dm *DenseMatrix) Rows() int { return dm.nY }
func (dm *DenseMatrix) Cols() int { return dm.nX }

func (dm *DenseMatrix) Get(row, col int) float32 {
	return dm.data[row*dm.nX+col]
}

func (dm *DenseMatrix) GetDiagonal(i int) float32 {
	return dm.Get(i, i)
}

func (dm *DenseMatrix) NonZeros() int {
	nonZeroCount := 0

	for _, value := range dm.data {
		if value != 0.0 {
			nonZeroCount++
		}
	}

	return nonZeroCount
}

func (dm *DenseMatrix) IsZero(row, col int) bool {
	return dm.data[row*dm.nX+col] == float32(0.0)
}

func (dm *DenseMatrix) Set(row, col int, value float32) {
	dm.data[row*dm.nX+col] = value
}

func (dm *DenseMatrix) SetDiagonal(i int, value float32) {
	dm.Set(i, i, value)
}

func (dm *DenseMatrix) Add(row, col int, value float32) {
	dm.data[row*dm.nX+col] += value
}

func (dm *DenseMatrix) AddDiagonal(i int, value float32) {
	dm.Add(i, i, value)
}

func (dm *DenseMatrix) Subtract(row, col int, value float32) {
	dm.data[row*dm.nX+col] -= value
}

func (dm *DenseMatrix) MatVec(x []float32) []float32 {
	if len(x) != dm.nY {
		panic(fmt.Sprintf("Cannot multiply an (%d, %d) matrix with a (%d, 1) vector", dm.nX, dm.nY, len(x)))
	}

	res := make([]float32, dm.nX)
	for i := range dm.nX {
		for j := range dm.nY {
			res[i] += dm.Get(i, j) * x[j]
		}
	}

	return res
}

func (dm *DenseMatrix) CopyFrom(other Matrix) {
	for i := range dm.Rows() {
		for j := range dm.Cols() {
			otherValue := other.Get(i, j)
			dm.Set(i, j, otherValue)
		}
	}
}

func (dm *DenseMatrix) Wipe() {
	for i := range dm.data {
		dm.data[i] = 0.0
	}
}

func (dm *DenseMatrix) ForEachInRow(row int, fn func(col int, val float32)) {
	startingIdx := row * dm.nX

	for j := 0; j < dm.nX; j++ {
		fn(j, dm.data[startingIdx+j])
	}
}

func (dm *DenseMatrix) String() string {
	var result strings.Builder

	for row := 0; row < dm.nY; row++ {
		result.WriteString("[")
		for col := 0; col < dm.nX; col++ {
			if col > 0 {
				result.WriteString(" ")
			}
			result.WriteString(fmt.Sprintf("%.2f", dm.data[row*dm.nX+col]))
		}
		result.WriteString("]")
		if row < dm.nY-1 {
			result.WriteString("\n")
		}
	}

	return result.String()
}
