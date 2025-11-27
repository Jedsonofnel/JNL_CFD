package nativedisp

import (
	"image/color"

	"github.com/hajimehoshi/ebiten/v2"
)

//
// Helper functions for colours in renderings
//

// NewColorScale creates a ColorScale from RGBA values (0-255)
func newColorScale(r, g, b, a uint8) ebiten.ColorScale {
	var cs ebiten.ColorScale
	cs.ScaleWithColor(color.RGBA{r, g, b, a})
	return cs
}

func csFromColor(c color.Color) ebiten.ColorScale {
	var cs ebiten.ColorScale
	cs.ScaleWithColor(c)
	return cs
}

func markerColor(marker int) color.Color {
	colors := map[int]color.Color{
		1: color.RGBA{255, 0, 0, 255},   // Red
		2: color.RGBA{0, 255, 0, 255},   // Green
		3: color.RGBA{0, 0, 255, 255},   // Blue
		4: color.RGBA{255, 255, 0, 255}, // Yellow
	}
	i := (marker % len(colors)) + 1
	if c, ok := colors[i]; ok {
		return c
	}
	return color.RGBA{0, 0, 0, 255}
}
