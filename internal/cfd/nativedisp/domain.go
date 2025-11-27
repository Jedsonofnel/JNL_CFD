//go:build !wasm

package nativedisp

import (
	"image/color"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

// for viewing a domain with ebitengine natively.
// Implements ebitengine.Game
type DomainViewer struct {
	domain           *geometry.Domain
	width, height    int
	scale            float64
	offsetX, offsetY float64

	regionColours func(int) color.Color
}

func NewDomainViewer(domain *geometry.Domain, width, height int) *DomainViewer {
	// Calculate scale to fit domain in window
	minX, minY, maxX, maxY := domain.Bounds()
	domainW, domainH := maxX-minX, maxY-minY

	scaleX := float64(width) * 0.9 / domainW
	scaleY := float64(height) * 0.9 / domainH
	scale := min(scaleX, scaleY)

	// Center the domain
	offsetX := float64(width)/2 - (minX+maxX)/2*scale
	offsetY := float64(height)/2 - (minY+maxY)/2*scale

	return &DomainViewer{
		domain:        domain,
		width:         width,
		height:        height,
		scale:         scale,
		offsetX:       offsetX,
		offsetY:       offsetY,
		regionColours: markerColor,
	}
}

func (v *DomainViewer) Update() error {
	return nil
}

func (v *DomainViewer) Draw(screen *ebiten.Image) {
	screen.Fill(color.RGBA{240, 240, 240, 255})

	for i := range v.domain.Polygons {
		poly := v.domain.Polygons[i]
		v.drawPoly(screen, poly, v.domain.GetLayer(i))
	}
}

func (v *DomainViewer) Layout(outsideWidth, outsideHeight int) (int, int) {
	return v.width, v.height
}

func (v *DomainViewer) drawPoly(screen *ebiten.Image, poly geometry.Polygon, layer int) {
	points := poly.Points

	// Build path
	var path vector.Path
	p0 := v.worldToScreen(points[0])
	path.MoveTo(float32(p0.X), float32(p0.Y))

	for i := 1; i < len(points); i++ {
		p := v.worldToScreen(points[i])
		path.LineTo(float32(p.X), float32(p.Y))
	}
	path.Close()

	dpoFill := &vector.DrawPathOptions{
		ColorScale: csFromColor(v.regionColours(layer)),
	}

	dpoStroke := &vector.DrawPathOptions{
		ColorScale: newColorScale(0, 0, 0, 255),
	}

	// Fill
	vector.FillPath(screen, &path, &vector.FillOptions{}, dpoFill)

	// Stroke outline
	vector.StrokePath(screen, &path, &vector.StrokeOptions{}, dpoStroke)
}

// translates a vector to screen dims
func (v *DomainViewer) worldToScreen(p geometry.Vec2) geometry.Vec2 {
	return geometry.Vec2{
		X: p.X*v.scale + v.offsetX,
		Y: float64(v.height) - (p.Y*v.scale + v.offsetY), // Flip Y
	}
}
