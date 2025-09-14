package renderer

import (
	"github.com/Jedsonofnel/cfd-but-wasm/geometry"
)

type RendererCore struct {
	// Geometry
	nX, nY        int
	width, height int
	rd            *geometry.RenderingData

	// Colour smoothing
	smoothedMax float32
	alpha       float32

	// Cell polygon rendering data
	verticesX, verticesY []float32
	trianglesPerCell     []int
	cellGreyscales       []float32
}

func NewRendererCore(nX, nY, width, height int, rd *geometry.RenderingData) *RendererCore {
	rc := &RendererCore{
		nX:             nX,
		nY:             nY,
		width:          width,
		height:         height,
		rd:             rd,
		smoothedMax:    1.0,
		alpha:          0.01,
		cellGreyscales: make([]float32, rd.NumCells),
	}

	rc.precomputeTriangles(rd)

	return rc
}

func (rc *RendererCore) precomputeTriangles(rd *geometry.RenderingData) {
	totalVertices := 0
	rc.trianglesPerCell = make([]int, rd.NumCells)
	for i := range rd.NumCells {
		triangleCount := rd.FaceStarts[i+1] - rd.FaceStarts[i] - 2
		rc.trianglesPerCell[i] = triangleCount
		totalVertices += triangleCount * 3 // three vertices per  triangle
	}

	rc.verticesX = make([]float32, totalVertices)
	rc.verticesY = make([]float32, totalVertices)

	vertexIdx := 0

	for i := range rd.NumCells {
		startIdx := rd.FaceStarts[i]
		endIdx := rd.FaceStarts[i+1]
		hubVertexIdx := rd.FaceIndices[startIdx]

		// fan triangulation
		for j := startIdx + 1; j < endIdx-1; j++ {
			v2, v3 := rd.FaceIndices[j], rd.FaceIndices[j+1]

			sv1x, sv1y := rc.physicsToScreen(rd.VerticesX[hubVertexIdx], rd.VerticesY[hubVertexIdx])
			rc.verticesX[vertexIdx] = sv1x
			rc.verticesY[vertexIdx] = sv1y

			sv2x, sv2y := rc.physicsToScreen(rd.VerticesX[v2], rd.VerticesY[v2])
			rc.verticesX[vertexIdx+1] = sv2x
			rc.verticesY[vertexIdx+1] = sv2y

			sv3x, sv3y := rc.physicsToScreen(rd.VerticesX[v3], rd.VerticesY[v3])
			rc.verticesX[vertexIdx+2] = sv3x
			rc.verticesY[vertexIdx+2] = sv3y

			vertexIdx += 3
		}
	}
}

func (rc *RendererCore) physicsToScreen(physX, physY float32) (float32, float32) {
	bounds := rc.rd.Bounds
	screenX := float32(rc.width) / bounds.Width * physX
	screenY := float32(rc.height) - float32(rc.height)/bounds.Height*physY
	return screenX, screenY
}

func (rc *RendererCore) ProcessField(vals []float32) {
	var currentMax float32 = 0.0
	for _, val := range vals {
		if val > currentMax {
			currentMax = val
		}
	}

	// exponential smoothing
	rc.smoothedMax = rc.alpha*currentMax + (1-rc.alpha)*rc.smoothedMax

	if rc.smoothedMax == 0.0 {
		// Set neutral colors and return
		for i := range vals {
			rc.cellGreyscales[i] = 0.5
		}
		return
	}

	for i, val := range vals {
		normalisedPhi := val / rc.smoothedMax
		rc.cellGreyscales[i] = 1.0 - normalisedPhi
	}
}
