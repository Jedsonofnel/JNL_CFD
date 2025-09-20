package field

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type systemAssemblyContext struct {
	Matrix         *linalg.CSR
	MatrixInternal *linalg.CSR

	RHS linalg.Vector

	BoundaryDiag    linalg.Vector
	BoundaryOffDiag linalg.Vector
}

func newSystemAssemblyContext(
	nCells, nBoundaries int,
	neighbourStarts, neighbourIndices []int,
) *systemAssemblyContext {
	matrix := linalg.NewCSRMatrixFromConnectivity(neighbourStarts, neighbourIndices)
	matrixInternal := linalg.NewCSRMatrixFromConnectivity(neighbourStarts, neighbourIndices)

	rhs := make(linalg.Vector, nCells)

	boundaryDiag := make(linalg.Vector, nBoundaries)
	boundaryOffDiag := make(linalg.Vector, nBoundaries)

	return &systemAssemblyContext{
		Matrix:          matrix,
		MatrixInternal:  matrixInternal,
		RHS:             rhs,
		BoundaryDiag:    boundaryDiag,
		BoundaryOffDiag: boundaryOffDiag,
	}
}

func (sys *systemAssemblyContext) SyncDecoratedMatrix() {
	sys.Matrix.CopyFrom(sys.MatrixInternal)
}

func (sys *systemAssemblyContext) PartialWipe() {
	sys.Matrix.Wipe()
	sys.RHS.Wipe()
}

func (sys *systemAssemblyContext) FullWipe() {
	sys.Matrix.Wipe()
	sys.MatrixInternal.Wipe()

	sys.RHS.Wipe()

	sys.BoundaryDiag.Wipe()
	sys.BoundaryOffDiag.Wipe()
}
