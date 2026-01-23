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
		if conn.Neighbour < 0 {
			continue // internal only
		}

		w := mesh.InterpWeights[i]
		faceField[i] = (1-w)*field[conn.Owner] + w*field[conn.Neighbour]
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
