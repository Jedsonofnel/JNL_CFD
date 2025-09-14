package field

import (
	"github.com/Jedsonofnel/cfd-but-wasm/geometry"
)

type UniformVelocity struct {
	velocitiesX, velocitiesY []float32
	timeDepX, timeDepY       func(t float32) float32
}

func NewUniformVelocityField(
	mesh *geometry.Mesh,
	timeDepX, timeDepY func(t float32) float32,
) *UniformVelocity {
	nCells := mesh.NumCells()
	return &UniformVelocity{
		velocitiesX: make([]float32, nCells),
		velocitiesY: make([]float32, nCells),
		timeDepX:    timeDepX,
		timeDepY:    timeDepY,
	}
}

func (uv *UniformVelocity) UpdateValues(t float32) {
	newX, newY := uv.timeDepX(t), uv.timeDepY(t)

	for i := range len(uv.velocitiesX) {
		uv.velocitiesX[i] = newX
		uv.velocitiesY[i] = newY
	}
}

func (uv *UniformVelocity) GetCellVelocityData() CellVelocityData {
	return CellVelocityData{
		VelocitiesX: uv.velocitiesX,
		VelocitiesY: uv.velocitiesY,
	}
}
