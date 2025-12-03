//go:build !wasm

package nativedisp

import (
	"image/color"

	"github.com/Jedsonofnel/jnlcfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type DomainViewer struct {
	domain           *geometry.Domain
	width, height    int
	scale            float64
	offsetX, offsetY float64
	regionColors     func(int) color.Color
}

func NewDomainViewer(domain *geometry.Domain, width, height int) *DomainViewer {
	minX, minY, maxX, maxY := domain.Bounds()
	domainW, domainH := maxX-minX, maxY-minY
	scaleX := float64(width) * 0.9 / domainW
	scaleY := float64(height) * 0.9 / domainH
	scale := min(scaleX, scaleY)

	offsetX := float64(width)/2 - (minX+maxX)/2*scale
	offsetY := float64(height)/2 - (minY+maxY)/2*scale

	return &DomainViewer{
		domain:       domain,
		width:        width,
		height:       height,
		scale:        scale,
		offsetX:      offsetX,
		offsetY:      offsetY,
		regionColors: GetRegionColor,
	}
}

func (v *DomainViewer) Update() error {
	return nil
}

func (v *DomainViewer) Draw(screen *ebiten.Image) {
	screen.Fill(Background)

	// Draw in reverse order so larger polygons don't cover smaller ones
	for i := len(v.domain.Polygons) - 1; i >= 0; i-- {
		poly := v.domain.Polygons[i]
		v.drawPolyFilled(screen, poly)
	}

	// Draw all outlines on top
	for i := range v.domain.Polygons {
		poly := v.domain.Polygons[i]
		v.drawPolyOutline(screen, poly)
	}
}

func (v *DomainViewer) Layout(outsideWidth, outsideHeight int) (int, int) {
	return v.width, v.height
}

func (v *DomainViewer) drawPolyFilled(screen *ebiten.Image, poly geometry.Polygon) {
	points := poly.Points

	var path vector.Path
	p0 := v.worldToScreen(points[0])
	path.MoveTo(float32(p0.X), float32(p0.Y))

	for i := 1; i < len(points); i++ {
		p := v.worldToScreen(points[i])
		path.LineTo(float32(p.X), float32(p.Y))
	}
	path.Close()

	// Color by regionID, not layer
	fillColor := v.regionColors(poly.RegionID)

	if poly.IsHole {
		fillColor = Background
	}

	dpoFill := &vector.DrawPathOptions{
		ColorScale: ColorScaleFromColor(fillColor),
	}

	vector.FillPath(screen, &path, &vector.FillOptions{}, dpoFill)
}

func (v *DomainViewer) drawPolyOutline(screen *ebiten.Image, poly geometry.Polygon) {
	points := poly.Points

	var path vector.Path
	p0 := v.worldToScreen(points[0])
	path.MoveTo(float32(p0.X), float32(p0.Y))

	for i := 1; i < len(points); i++ {
		p := v.worldToScreen(points[i])
		path.LineTo(float32(p.X), float32(p.Y))
	}
	path.Close()

	// Thicker outline for holes
	lineWidth := 1.0
	lineColor := EdgeDark
	if poly.IsHole {
		lineWidth = 2.0
		lineColor = HoleOutline
	}

	dpoStroke := &vector.DrawPathOptions{
		ColorScale: ColorScaleFromColor(lineColor),
	}

	vector.StrokePath(screen, &path, &vector.StrokeOptions{
		Width: float32(lineWidth),
	}, dpoStroke)
}

func (v *DomainViewer) worldToScreen(p geometry.Vec2) geometry.Vec2 {
	return geometry.Vec2{
		X: p.X*v.scale + v.offsetX,
		Y: float64(v.height) - (p.Y*v.scale + v.offsetY),
	}
}
