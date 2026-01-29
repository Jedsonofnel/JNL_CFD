package fvm

import (
	"errors"
	"math"

	"jedn.dev/jnlcfd/geometry"
)

//
// Face value reconstruction
//

// InternalConnInterp updates connField for every internal connection using CDS
func FaceInterpCDS(mesh *geometry.Mesh, field, faceField []float64) {
	for i, conn := range mesh.Connections {
		if conn.Neighbour >= 0 {
			w := mesh.InterpWeights[i]
			faceField[i] = (1-w)*field[conn.Owner] + w*field[conn.Neighbour]
		} else {
			faceField[i] = field[conn.Owner] // zero-gradient default
		}
	}
}

func FaceNormalComponent(mesh *geometry.Mesh, UxFace, UyFace, Unormal []float64) {
	for i := range Unormal {
		n := mesh.FaceNormals[i]
		Unormal[i] = UxFace[i]*n.X + UyFace[i]*n.Y
	}
}

func DirichletFaceValuesConst(mesh *geometry.Mesh, faceField []float64, boundaryName string, value float64) {
	faceIndices := mesh.BoundaryFaces[boundaryName]
	for _, connIdx := range faceIndices {
		faceField[connIdx] = value
	}
}

func NeumannFaceValuesConst(mesh *geometry.Mesh, field, faceField []float64, boundaryName string, flux float64) {
	faceIndices := mesh.BoundaryFaces[boundaryName]
	for _, connIdx := range faceIndices {
		owner := mesh.Connections[connIdx].Owner
		dist := mesh.ConnectionDists[connIdx]
		faceField[connIdx] = field[owner] + flux*dist
	}
}

func RhieChowFaceNormal(
	mesh *geometry.Mesh,
	Ux, Uy []float64,
	p []float64,
	gradPx, gradPy []float64,
	aPx, aPy []float64,
	UnormalMWI []float64,
) {
	for i, conn := range mesh.Connections {
		n := mesh.FaceNormals[i]
		owner := conn.Owner

		dxOwner := mesh.CellVolumes[owner] / aPx[owner]
		dyOwner := mesh.CellVolumes[owner] / aPy[owner]
		UnOwner := Ux[owner]*n.X + Uy[owner]*n.Y
		gradPnOwner := gradPx[owner]*n.X + gradPy[owner]*n.Y

		if conn.Neighbour >= 0 {
			neigh := conn.Neighbour
			w := mesh.InterpWeights[i]

			dxNeigh := mesh.CellVolumes[neigh] / aPx[neigh]
			dyNeigh := mesh.CellVolumes[neigh] / aPy[neigh]
			UnNeigh := Ux[neigh]*n.X + Uy[neigh]*n.Y
			gradPnNeigh := gradPx[neigh]*n.X + gradPy[neigh]*n.Y

			UnInterp := (1-w)*UnOwner + w*UnNeigh
			dxFace := (1-w)*dxOwner + w*dxNeigh
			dyFace := (1-w)*dyOwner + w*dyNeigh
			gradPnInterp := (1-w)*gradPnOwner + w*gradPnNeigh

			// Direct pressure gradient with non-orthogonality correction
			pDiff := p[neigh] - p[owner]
			dist := mesh.ConnectionDists[i]
			gradPxFace := (1-w)*gradPx[owner] + w*gradPx[neigh]
			gradPyFace := (1-w)*gradPy[owner] + w*gradPy[neigh]

			delta := mesh.NonOrthDeltas[i]
			gradPnDirect := mesh.OrthFactors[i]*pDiff/dist + delta.X*gradPxFace + delta.Y*gradPyFace

			dNormal := dxFace*n.X*n.X + dyFace*n.Y*n.Y
			UnormalMWI[i] = UnInterp - dNormal*(gradPnDirect-gradPnInterp)
		} else {
			UnormalMWI[i] = UnOwner
		}
	}
}

//
// Gradient reconstruction
//

func GreenGaussGradient(
	mesh *geometry.Mesh,
	faceField []float64,
	gradX, gradY []float64,
) {
	for i := range gradX {
		gradX[i], gradY[i] = 0, 0
	}

	for i, conn := range mesh.Connections {
		flux := faceField[i] * mesh.FaceAreas[i]
		nx, ny := mesh.FaceNormals[i].X, mesh.FaceNormals[i].Y

		gradX[conn.Owner] += flux * nx
		gradY[conn.Owner] += flux * ny

		if conn.Neighbour >= 0 {
			gradX[conn.Neighbour] -= flux * nx
			gradY[conn.Neighbour] -= flux * ny
		}
	}

	for i := range gradX {
		vol := mesh.CellVolumes[i]
		gradX[i] /= vol
		gradY[i] /= vol
	}
}

//
// Divergence
//

func Divergence(mesh *geometry.Mesh, UnFace []float64, div []float64) {
	for i := range div {
		div[i] = 0
	}
	for f, conn := range mesh.Connections {
		flux := UnFace[f] * mesh.FaceAreas[f]
		if conn.Owner >= 0 {
			div[conn.Owner] += flux
		}
		if conn.Neighbour >= 0 {
			div[conn.Neighbour] -= flux
		}
	}
}

//
// For rendering
//

func UpdateTriField(triField, results []float64, triToCells []int) error {
	if len(triField) != len(triToCells)*3 {
		return errors.New("triField does not have the right length")
	}

	maxResult, minResult := -math.MaxFloat64, math.MaxFloat64

	for i := range results {
		maxResult = max(maxResult, results[i])
		minResult = min(minResult, results[i])
	}

	resultRange := maxResult - minResult

	for triIdx, cellIdx := range triToCells {
		res := results[cellIdx]
		normalised := (res - minResult) / resultRange
		triField[triIdx*3+0] = normalised
		triField[triIdx*3+1] = normalised
		triField[triIdx*3+2] = normalised
	}

	return nil
}
