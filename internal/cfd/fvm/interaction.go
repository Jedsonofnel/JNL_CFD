package fvm

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

// RENDERING

type RenderData struct {
	// from MeshRenderData
	TriangleVertices []float32
	TriangleStarts   []int

	// colour data itself
	TriangleVertexColours []float32

	// important for canvas stuff
	Width, Height float32

	// smoothing parameters
	smoothedMax float32
	alpha       float32
}

func NewRenderData(scenario Scenario) *RenderData {
	mesh := scenario.GetMesh()
	mrd := geometry.NewMeshRenderData(mesh)

	triangleVertices := mrd.TriangleVertices
	triangleStarts := mrd.TriangleStarts
	triangleVertexColours := make([]float32, len(triangleVertices)/2)

	fieldVals := scenario.getTracerFieldValues()

	var currentMax float32
	for _, val := range fieldVals {
		if val > currentMax {
			currentMax = val
		}
	}

	return &RenderData{
		TriangleVertices:      triangleVertices,
		TriangleStarts:        triangleStarts,
		TriangleVertexColours: triangleVertexColours,

		Width:  mrd.Width,
		Height: mrd.Height,

		smoothedMax: currentMax,
		alpha:       0.01,
	}
}

func NormaliseResults(rd *RenderData, results []float32) []float32 {
	var currentMax float32 = 0
	for _, val := range results {
		if val > currentMax {
			currentMax = val
		}
	}

	if rd.smoothedMax == 0 {
		rd.smoothedMax = 1e-12
	}

	rd.smoothedMax = rd.alpha*currentMax + (1-rd.alpha)*rd.smoothedMax

	for i, res := range results {
		normalisedResult := res / rd.smoothedMax

		startIdx, endIdx := rd.TriangleStarts[i], rd.TriangleStarts[i+1]
		for vi := startIdx; vi < endIdx; vi++ {
			rd.TriangleVertexColours[vi] = normalisedResult
		}
	}

	return rd.TriangleVertexColours
}

// POINT SOURCE POSITION

type ScalarPointSourceHandler struct {
	mesh     *geometry.Mesh
	operator *scalarOperator

	setupPoints []Vec2
	setupValues []float32
}

func NewScalarPointSourceHandler() *ScalarPointSourceHandler {
	return &ScalarPointSourceHandler{
		setupPoints: make([]Vec2, 0),
		setupValues: make([]float32, 0),
	}
}

func (ps *ScalarPointSourceHandler) SetPointSource(x, y, value float32) error {
	if x < -1 || x > 1 || y < -1 || y > 1 {
		return fmt.Errorf("SetPointSource > requires x/y in [-1, 1] space.")
	}

	// ie in definition phase
	if ps.mesh == nil || ps.operator == nil {
		ps.setupPoints = append(ps.setupPoints, Vec2{x, y})
		ps.setupValues = append(ps.setupValues, value)
		return nil
	}

	physX, physY := geometry.NormalisedToPhysics(ps.mesh, x, y)
	cellIdx := geometry.FindNearestCell(ps.mesh, physX, physY)

	ps.operator.fluxes[cellIdx] = value

	return nil
}
