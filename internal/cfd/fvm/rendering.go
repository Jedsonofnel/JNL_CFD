package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

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
	mesh := scenario.getMesh()
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
