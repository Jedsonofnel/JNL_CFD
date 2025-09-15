//go:build !wasm

package renderer

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"image/color"
)

type NativeRenderer struct {
	core *RendererCore

	// ebiten specific vertices mirrors core.vertices
	vertices []ebiten.Vertex
	indices  []uint16

	whiteTexture *ebiten.Image
}

func NewNativeRenderer(nX, nY, width, height int, rd *geometry.RenderingData) *NativeRenderer {
	core := NewRendererCore(nX, nY, width, height, rd)

	whiteTexture := ebiten.NewImage(1, 1)
	whiteTexture.Fill(color.RGBA{255, 255, 255, 255})

	nr := &NativeRenderer{
		core:         core,
		vertices:     make([]ebiten.Vertex, len(core.verticesX)),
		indices:      make([]uint16, len(core.verticesX)),
		whiteTexture: whiteTexture,
	}

	nr.translateVertices()
	return nr
}

func (nr *NativeRenderer) translateVertices() {
	for i := range len(nr.core.verticesX) {
		nr.vertices[i] = ebiten.Vertex{
			DstX:   nr.core.verticesX[i],
			DstY:   nr.core.verticesY[i],
			SrcX:   0.5,
			SrcY:   0.5,
			ColorR: 0.0,
			ColorG: 0.0,
			ColorB: 0.0,
			ColorA: 0.0,
		}
		nr.indices[i] = uint16(i)
	}
}

func (nr *NativeRenderer) DrawToScreen(screen *ebiten.Image, tracerConcs []float32) {
	screen.Fill(color.RGBA{255, 255, 255, 255})

	nr.core.ProcessField(tracerConcs)

	traversedTris := 0
	for i, greyscale := range nr.core.cellGreyscales {
		for v := range nr.core.trianglesPerCell[i] * 3 {
			vIdx := traversedTris*3 + v
			nr.vertices[vIdx].ColorR = greyscale
			nr.vertices[vIdx].ColorG = greyscale
			nr.vertices[vIdx].ColorB = greyscale
			nr.vertices[vIdx].ColorA = 1.0
		}

		traversedTris += nr.core.trianglesPerCell[i]
	}

	screen.DrawTriangles(nr.vertices, nr.indices, nr.whiteTexture, &ebiten.DrawTrianglesOptions{})
}
