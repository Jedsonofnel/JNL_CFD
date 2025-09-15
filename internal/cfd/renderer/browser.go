//go:build wasm

package renderer

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"strconv"
	"syscall/js"
)

const (
	canvasID           = "cfd-canvas"
	nominalScreenWidth = 800
)

type Renderer struct {
	// Geometry
	mesh *geometry.Mesh

	// Colour smoothing
	smoothedMax float32
	alpha       float32

	// Cell polygon rendering data
	verticesX, verticesY []float32
	trianglesPerCell     []int
	cellGreyscales       []float32

	// js
	ctx             js.Value
	cWidth, cHeight float32
}

func NewRenderer(mesh *geometry.Mesh) *Renderer {
	vX, vY, tris := computeCellTris(mesh)

	canvas := js.Global().Get("document").Call("getElementById", canvasID)
	cWidth, _ := getCanvasDimensions(canvas)

	sf := mesh.Bounds.Width / float32(cWidth)
	desiredHeight := mesh.Bounds.Height / sf
	canvas.Call("setAttribute", "height", desiredHeight)

	ctx := canvas.Call("getContext", "2d")

	r := &Renderer{
		mesh:             mesh,
		smoothedMax:      1.0,
		alpha:            0.01,
		verticesX:        vX,
		verticesY:        vY,
		trianglesPerCell: tris,
		cellGreyscales:   make([]float32, mesh.NumCells()),
		ctx:              ctx,
		cWidth:           float32(cWidth),
		cHeight:          desiredHeight,
	}

	return r
}

func computeCellTris(mesh *geometry.Mesh) ([]float32, []float32, []int) {
	totalVertices := 0
	tris := make([]int, mesh.NumCells())

	for i := range mesh.NumCells() {
		triangleCount := mesh.FaceStarts[i+1] - mesh.FaceStarts[i] - 2
		tris[i] = triangleCount
		totalVertices += triangleCount * 3 // three vertices per triangle
	}

	vX, vY := make([]float32, totalVertices), make([]float32, totalVertices)
	vIdx := 0

	for i := range mesh.NumCells() {
		startIdx, endIdx := mesh.FaceStarts[i], mesh.FaceStarts[i+1]
		hubVertexIdx := mesh.FaceIndices[startIdx]

		// fan triangulation
		for j := startIdx + 1; j < endIdx-1; j++ {
			v2, v3 := mesh.FaceIndices[j], mesh.FaceIndices[j+1]

			sv1x, sv1y := physicsToScreen(
				mesh.VerticesX[hubVertexIdx],
				mesh.VerticesY[hubVertexIdx],
				mesh,
			)
			vX[vIdx] = sv1x
			vY[vIdx] = sv1y

			sv2x, sv2y := physicsToScreen(mesh.VerticesX[v2], mesh.VerticesY[v2], mesh)
			vX[vIdx+1] = sv2x
			vY[vIdx+1] = sv2y

			sv3x, sv3y := physicsToScreen(mesh.VerticesX[v3], mesh.VerticesY[v3], mesh)
			vX[vIdx+2] = sv3x
			vY[vIdx+2] = sv3y

			vIdx += 3
		}
	}

	return vX, vY, tris
}

func physicsToScreen(physX, physY float32, mesh *geometry.Mesh) (float32, float32) {
	bounds := mesh.Bounds
	sf := float32(nominalScreenWidth) / bounds.Width
	screenX := sf * physX
	screenY := bounds.Height/sf - sf*physY
	return screenX, screenY
}

func (r *Renderer) ProcessField(vals []float32) {
	var currentMax float32 = 0.0
	for _, val := range vals {
		if val > currentMax {
			currentMax = val
		}
	}

	// exponential smoothing
	r.smoothedMax = r.alpha*currentMax + (1-r.alpha)*r.smoothedMax

	if r.smoothedMax == 0.0 {
		// Set neutral colors and return
		for i := range vals {
			r.cellGreyscales[i] = 0.5
		}
		return
	}

	for i, val := range vals {
		normalisedPhi := val / r.smoothedMax
		r.cellGreyscales[i] = 1.0 - normalisedPhi
	}
}

func (r *Renderer) RenderMesh() {
	r.ctx.Set("fillStyle", "white")
	r.ctx.Call("fillRect", 0, 0, r.cWidth, r.cHeight)
	println("HELLO")
}

func getCanvasDimensions(c js.Value) (width, height int) {
	widthString := c.Call("getAttribute", "width").String()
	heightString := c.Call("getAttribute", "height").String()

	width, err := strconv.Atoi(widthString)
	if err != nil {
		panic("Canvas width attribute needs to be an integer")
	}

	height, err = strconv.Atoi(heightString)
	if err != nil {
		panic("Canvas height attribute needs to be an integer")
	}
	return width, height
}
