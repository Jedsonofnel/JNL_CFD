//go:build !wasm

package nativedisp

import (
	"image/color"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

// for viewing a domain and eventually a mesh with ebitengine natively.
// Implements ebitengine.Game
type Viewer struct {
	domain           *geometry.Domain
	width, height    int
	scale            float64
	offsetX, offsetY float64

	regionColours func(int) ebiten.ColorScale
}

func NewViewer(domain *geometry.Domain, width, height int) *Viewer {
	domain.ComputeLayers()

	// Calculate scale to fit domain in window
	minX, minY, maxX, maxY := domain.Bounds()
	domainW, domainH := maxX-minX, maxY-minY

	scaleX := float64(width) * 0.9 / domainW
	scaleY := float64(height) * 0.9 / domainH
	scale := min(scaleX, scaleY)

	// Center the domain
	offsetX := float64(width)/2 - (minX+maxX)/2*scale
	offsetY := float64(height)/2 - (minY+maxY)/2*scale

	return &Viewer{
		domain:        domain,
		width:         width,
		height:        height,
		scale:         scale,
		offsetX:       offsetX,
		offsetY:       offsetY,
		regionColours: makeColourFunc(domain),
	}
}

func (v *Viewer) Update() error {
	return nil
}

func (v *Viewer) Draw(screen *ebiten.Image) {
	screen.Fill(color.RGBA{240, 240, 240, 255})

	for i, shape := range v.domain.Shapes() {
		v.drawShape(screen, shape, v.domain.GetLayer(i))
	}
}

func (v *Viewer) Layout(outsideWidth, outsideHeight int) (int, int) {
	return v.width, v.height
}

func (v *Viewer) drawShape(screen *ebiten.Image, shape geometry.Shape, layer int) {
	points, _, _ := shape.ToPSLG(0)

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
		ColorScale: v.regionColours(layer),
	}

	dpoStroke := &vector.DrawPathOptions{
		ColorScale: newColorScale(0, 0, 0, 255),
	}

	// Fill
	vector.FillPath(screen, &path, &vector.FillOptions{}, dpoFill)

	// Stroke outline
	vector.StrokePath(screen, &path, &vector.StrokeOptions{}, dpoStroke)
}

//
// Helpers
//

// translates a vector to screen dims
func (v *Viewer) worldToScreen(p geometry.Vec2) geometry.Vec2 {
	return geometry.Vec2{
		X: p.X*v.scale + v.offsetX,
		Y: float64(v.height) - (p.Y*v.scale + v.offsetY), // Flip Y
	}
}

// NewColorScale creates a ColorScale from RGBA values (0-255)
func newColorScale(r, g, b, a uint8) ebiten.ColorScale {
	var cs ebiten.ColorScale
	cs.ScaleWithColor(color.RGBA{r, g, b, a})
	return cs
}

// generates colours to loop through when drawing
func makeColourFunc(_ *geometry.Domain) func(int) ebiten.ColorScale {
	colours := map[int]ebiten.ColorScale{
		1: newColorScale(100, 150, 255, 255), // Blue
		2: newColorScale(255, 100, 100, 255), // Red
		3: newColorScale(100, 255, 100, 255), // Green
		4: newColorScale(255, 200, 100, 255), // Orange
	}

	return func(layer int) ebiten.ColorScale {
		i := (layer % 4) + 1
		c := colours[i]
		return c
	}
}
