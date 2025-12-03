//go:build !wasm

package nativedisp

import (
	"image/color"

	"github.com/Jedsonofnel/jnlcfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type SolutionViewer struct {
	mesh             *geometry.Mesh
	fieldValues      []float64
	width, height    int
	scale            float64
	offsetX, offsetY float64

	showEdges bool
	edgeColor color.Color

	minValue, maxValue float64
	colormap           func(float64) color.Color

	triangleVertices []ebiten.Vertex
	triangleIndices  []uint16
	whiteImage       *ebiten.Image
}

func NewSolutionViewer(mesh *geometry.Mesh, fieldValues []float64,
	width, height int) *SolutionViewer {
	minX, minY := mesh.Vertices[0].X, mesh.Vertices[0].Y
	maxX, maxY := minX, minY

	for _, v := range mesh.Vertices[1:] {
		if v.X < minX {
			minX = v.X
		}
		if v.X > maxX {
			maxX = v.X
		}
		if v.Y < minY {
			minY = v.Y
		}
		if v.Y > maxY {
			maxY = v.Y
		}
	}

	domainW, domainH := maxX-minX, maxY-minY
	scaleX := float64(width) * 0.9 / domainW
	scaleY := float64(height) * 0.9 / domainH
	scale := min(scaleX, scaleY)

	offsetX := float64(width)/2 - (minX+maxX)/2*scale
	offsetY := float64(height)/2 - (minY+maxY)/2*scale

	whiteImage := ebiten.NewImage(1, 1)
	whiteImage.Fill(color.White)

	minVal, maxVal := fieldValues[0], fieldValues[0]
	for _, v := range fieldValues[1:] {
		if v < minVal {
			minVal = v
		}
		if v > maxVal {
			maxVal = v
		}
	}

	v := &SolutionViewer{
		mesh:        mesh,
		fieldValues: fieldValues,
		width:       width,
		height:      height,
		scale:       scale,
		offsetX:     offsetX,
		offsetY:     offsetY,
		showEdges:   true,
		edgeColor:   color.RGBA{50, 50, 50, 100},
		minValue:    minVal,
		maxValue:    maxVal,
		colormap:    Jet,
		whiteImage:  whiteImage,
	}

	v.buildTriangleCache()
	return v
}

func (v *SolutionViewer) Update() error {
	return nil
}

func (v *SolutionViewer) Draw(screen *ebiten.Image) {
	screen.Fill(color.RGBA{240, 240, 240, 255})

	if len(v.triangleVertices) > 0 {
		screen.DrawTriangles(v.triangleVertices, v.triangleIndices,
			v.whiteImage, nil)
	}

	if v.showEdges {
		v.drawEdges(screen)
	}
}

func (v *SolutionViewer) Layout(outsideWidth, outsideHeight int) (int, int) {
	return v.width, v.height
}

// buildTriangleCache handles arbitrary polygons
func (v *SolutionViewer) buildTriangleCache() {
	nCells := len(v.mesh.FaceStarts) - 1

	v.triangleVertices = make([]ebiten.Vertex, 0, nCells*4*3)
	v.triangleIndices = make([]uint16, 0, nCells*4*3)

	vertexCount := uint16(0)

	for cellID := 0; cellID < nCells; cellID++ {
		// Get cell value and color
		cellValue := v.fieldValues[cellID]
		col := v.colormap(cellValue)
		r, g, b, a := col.RGBA()

		rf := float32(r) / 0xffff
		gf := float32(g) / 0xffff
		bf := float32(b) / 0xffff
		af := float32(a) / 0xffff

		// Get vertices and triangulate
		vertices := GetCellVertices(v.mesh, cellID)
		centroid := v.mesh.Centroids[cellID]
		triangles := CentroidTriangulate(vertices, centroid)

		// Add to GPU buffers
		for _, tri := range triangles {
			for _, vert := range []geometry.Vec2{tri.V0, tri.V1, tri.V2} {
				p := v.worldToScreen(vert)

				v.triangleVertices = append(v.triangleVertices, ebiten.Vertex{
					DstX:   float32(p.X),
					DstY:   float32(p.Y),
					SrcX:   0,
					SrcY:   0,
					ColorR: rf,
					ColorG: gf,
					ColorB: bf,
					ColorA: af,
				})

				v.triangleIndices = append(v.triangleIndices, vertexCount)
				vertexCount++
			}
		}
	}
}

func (v *SolutionViewer) drawEdges(screen *ebiten.Image) {
	nCells := len(v.mesh.FaceStarts) - 1

	for cellID := 0; cellID < nCells; cellID++ {
		startIdx := v.mesh.FaceStarts[cellID]
		endIdx := v.mesh.FaceStarts[cellID+1]

		for faceIdx := startIdx; faceIdx < endIdx; faceIdx++ {
			nextFaceIdx := startIdx + (faceIdx-startIdx+1)%(endIdx-startIdx)

			v0 := v.mesh.Vertices[v.mesh.VertexIndices[faceIdx]]
			v1 := v.mesh.Vertices[v.mesh.VertexIndices[nextFaceIdx]]

			p0 := v.worldToScreen(v0)
			p1 := v.worldToScreen(v1)

			vector.StrokeLine(screen,
				float32(p0.X), float32(p0.Y),
				float32(p1.X), float32(p1.Y),
				0.5, v.edgeColor, false)
		}
	}
}

func (v *SolutionViewer) worldToScreen(p geometry.Vec2) geometry.Vec2 {
	return geometry.Vec2{
		X: p.X*v.scale + v.offsetX,
		Y: float64(v.height) - (p.Y*v.scale + v.offsetY),
	}
}
