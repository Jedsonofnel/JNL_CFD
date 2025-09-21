package geometry

import (
	"math"
)

// normalised = [-1, 1]
func NormalisedToPhysics(mesh *Mesh, x, y float32) (physX, physY float32) {
	sfX, sfY := mesh.Bounds.Width/2, mesh.Bounds.Height/2
	physX = (x * sfX) + sfX
	physY = (y * sfY) + sfY

	return
}

// physics coords
func FindNearestCell(mesh *Mesh, x, y float32) (cellIdx int) {
	var minDist float32 = math.MaxFloat32

	for i := range mesh.NumCells() {
		dX := x - mesh.CentroidsX[i]
		dY := y - mesh.CentroidsY[i]
		distSqrd := (dX * dX) + (dY * dY)
		if distSqrd < minDist {
			minDist = distSqrd
			cellIdx = i
		}
	}

	return
}
