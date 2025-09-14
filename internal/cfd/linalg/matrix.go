package linalg

type Matrix interface {
	// Dimensions
	Rows() int
	Cols() int

	// Element access
	Get(i, j int) float32
	GetDiagonal(i int) float32

	// Matrix properties
	NonZeros() int
	IsZero(i, j int) bool

	// Element manipulation
	Set(i, j int, value float32)
	SetDiagonal(i int, value float32)
	Add(i, j int, value float32)
	AddDiagonal(i int, value float32)
	Subtract(i, j int, value float32)

	// Bulk operations
	MatVec(x []float32) []float32
	CopyFrom(other Matrix)
	Wipe()

	// Callback exposures
	ForEachInRow(i int, fn func(j int, value float32))
	// ForEachNonZero(fn func(row, col int, val float32)) YAGNI
}
