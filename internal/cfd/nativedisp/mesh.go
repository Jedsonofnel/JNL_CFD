//go:build !wasm

package nativedisp

import (
	"image/color"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type MeshViewer struct {
	mesh             *geometry.Mesh
	width, height    int
	scale            float64
	offsetX, offsetY float64

	showEdges        bool
	showBoundaryOnly bool
	regionColors     func(int) color.Color
	edgeColor        color.Color

	triangleVertices []ebiten.Vertex
	triangleIndices  []uint16
	whiteImage       *ebiten.Image
}

func NewMeshViewer(mesh *geometry.Mesh, width, height int) *MeshViewer {
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

	v := &MeshViewer{
		mesh:             mesh,
		width:            width,
		height:           height,
		scale:            scale,
		offsetX:          offsetX,
		offsetY:          offsetY,
		showEdges:        true,
		showBoundaryOnly: false,
		edgeColor:        color.RGBA{50, 50, 50, 255},
		regionColors:     makeRegionColorFunc(mesh),
		whiteImage: whiteImage,
	}

	v.buildTriangleCache()
	return v
}

func (v *MeshViewer) Update() error {
	return nil
}

func (v *MeshViewer) Draw(screen *ebiten.Image) {
	screen.Fill(color.RGBA{240, 240, 240, 255})

	if len(v.triangleVertices) > 0 {
		screen.DrawTriangles(v.triangleVertices, v.triangleIndices,
			v.whiteImage, nil)
	}

	if v.showEdges {
		if v.showBoundaryOnly {
			v.drawBoundaryEdges(screen)
		} else {
			v.drawAllEdges(screen)
		}
	}
}

func (v *MeshViewer) Layout(outsideWidth, outsideHeight int) (int, int) {
	return v.width, v.height
}

// buildTriangleCache handles arbitrary polygons via centroid triangulation
func (v *MeshViewer) buildTriangleCache() {
	nCells := len(v.mesh.FaceStarts) - 1

	// Estimate capacity (assume avg 4 vertices per cell -> 4 triangles)
	v.triangleVertices = make([]ebiten.Vertex, 0, nCells*4*3)
	v.triangleIndices = make([]uint16, 0, nCells*4*3)

	vertexCount := uint16(0)

	for cellID := 0; cellID < nCells; cellID++ {
		// Get region color
		region := 0
		if cellID < len(v.mesh.CellRegions) {
			region = v.mesh.CellRegions[cellID]
		}
		col := v.regionColors(region)
		r, g, b, a := col.RGBA()

		rf := float32(r) / 0xffff
		gf := float32(g) / 0xffff
		bf := float32(b) / 0xffff
		af := float32(a) / 0xffff

		// Get cell vertices and centroid
		vertices := GetCellVertices(v.mesh, cellID)
		centroid := v.mesh.Centroids[cellID]

		// Triangulate using centroid
		triangles := CentroidTriangulate(vertices, centroid)

		// Add triangles to GPU buffers
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

func (v *MeshViewer) drawAllEdges(screen *ebiten.Image) {
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
				1.0, v.edgeColor, false)
		}
	}
}

func (v *MeshViewer) drawBoundaryEdges(screen *ebiten.Image) {
	for connIdx := range v.mesh.Connections {
		conn := v.mesh.Connections[connIdx]

		if conn.Neighbour >= 0 {
			continue
		}

		v0, v1 := v.mesh.GetConnectionVertices(connIdx)
		p0 := v.worldToScreen(v0)
		p1 := v.worldToScreen(v1)

		lineColor := v.edgeColor
		if conn.Marker != 0 {
			lineColor = markerColor(int(conn.Marker))
		}

		vector.StrokeLine(screen,
			float32(p0.X), float32(p0.Y),
			float32(p1.X), float32(p1.Y),
			2.0, lineColor, false)
	}
}

func (v *MeshViewer) worldToScreen(p geometry.Vec2) geometry.Vec2 {
	return geometry.Vec2{
		X: p.X*v.scale + v.offsetX,
		Y: float64(v.height) - (p.Y*v.scale + v.offsetY),
	}
}

func makeRegionColorFunc(mesh *geometry.Mesh) func(int) color.Color {
	colors := map[int]color.Color{
		0: color.RGBA{200, 200, 200, 255},
		1: color.RGBA{100, 150, 255, 255},
		2: color.RGBA{255, 100, 100, 255},
		3: color.RGBA{100, 255, 100, 255},
		4: color.RGBA{255, 200, 100, 255},
	}

	return func(region int) color.Color {
		if c, ok := colors[region]; ok {
			return c
		}
		return color.RGBA{
			uint8((region * 67) % 256),
			uint8((region * 113) % 256),
			uint8((region * 191) % 256),
			255,
		}
	}
}
