package simulation

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
)

type RenderData struct {
	// from MeshRenderData
	TriangleVertices []float32
	TriangleStarts   []int

	// colour data itself
	TriangleVertexColours []float32

	// smoothing parameters
	smoothedMax float32
	alpha       float32
}

func NewRenderData(mrd *geometry.MeshRenderData) *RenderData {
	triangleVertices := mrd.TriangleVertices
	triangleStarts := mrd.TriangleStarts
	triangleVertexColours := make([]float32, len(triangleVertices)/2)

	return &RenderData{
		TriangleVertices:      triangleVertices,
		TriangleStarts:        triangleStarts,
		TriangleVertexColours: triangleVertexColours,

		smoothedMax: 0.0,
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

	rd.smoothedMax = rd.alpha*currentMax + (1-rd.alpha)*rd.smoothedMax

	for i, res := range results {
		normalisedResult := res / rd.smoothedMax

		startIdx, endIdx := rd.TriangleStarts[i]/2, rd.TriangleStarts[i+1]/2
		for vi := startIdx; vi < endIdx; vi++ {
			rd.TriangleVertexColours[vi] = normalisedResult
		}
	}

	return rd.TriangleVertexColours
}
