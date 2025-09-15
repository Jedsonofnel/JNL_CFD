package field

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type systemAssemblyContext struct {
	Matrix         linalg.Matrix
	MatrixInternal linalg.Matrix

	RHS linalg.Vector

	BoundaryDiag    linalg.Vector
	BoundaryOffDiag linalg.Vector
}

func (sys *systemAssemblyContext) SyncDecoratedMatrix() {
	sys.Matrix.CopyFrom(sys.MatrixInternal)
}

func (sys *systemAssemblyContext) Wipe() {
	sys.Matrix.Wipe()
	sys.MatrixInternal.Wipe()

	sys.RHS.Wipe()

	sys.BoundaryDiag.Wipe()
	sys.BoundaryOffDiag.Wipe()
}
