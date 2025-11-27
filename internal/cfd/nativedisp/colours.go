package nativedisp

import (
	"image/color"
	"math"

	"github.com/hajimehoshi/ebiten/v2"
)

//
// Core UI colors
//

var (
	Background  = color.RGBA{245, 245, 245, 255} // Light gray background
	Foreground  = color.RGBA{30, 30, 30, 255}    // Dark text/lines
	EdgeDark    = color.RGBA{50, 50, 50, 255}    // Mesh edges
	EdgeLight   = color.RGBA{140, 140, 140, 255} // Lighter edges
	HoleOutline = color.RGBA{200, 0, 0, 180}     // Red with alpha for holes
)

//
// Soft overlay colors (low alpha for visualization)
//

var (
	SoftRed    = color.RGBA{255, 100, 100, 120}
	SoftOrange = color.RGBA{255, 180, 100, 120}
	SoftYellow = color.RGBA{255, 235, 100, 120}
	SoftGreen  = color.RGBA{120, 255, 140, 120}
	SoftCyan   = color.RGBA{100, 220, 255, 120}
	SoftBlue   = color.RGBA{100, 150, 255, 120}
	SoftPurple = color.RGBA{180, 120, 255, 120}
	SoftPink   = color.RGBA{255, 120, 200, 120}
)

//
// Region palette - general purpose, similar saturation
//

var RegionPalette = []color.Color{
	color.RGBA{200, 200, 200, 255}, // 0: Light gray (default/background)
	color.RGBA{100, 150, 255, 255}, // 1: Blue
	color.RGBA{255, 120, 100, 255}, // 2: Coral red
	color.RGBA{120, 220, 140, 255}, // 3: Green
	color.RGBA{255, 200, 100, 255}, // 4: Orange
	color.RGBA{180, 120, 255, 255}, // 5: Purple
	color.RGBA{100, 220, 220, 255}, // 6: Cyan
	color.RGBA{255, 180, 200, 255}, // 7: Pink
	color.RGBA{200, 200, 100, 255}, // 8: Yellow-green
	color.RGBA{150, 150, 255, 255}, // 9: Light blue
	color.RGBA{255, 150, 100, 255}, // 10: Light orange
	color.RGBA{140, 200, 140, 255}, // 11: Sage green
}

// GetRegionColor returns a color for a region ID
func GetRegionColor(regionID int) color.Color {
	if regionID >= 0 && regionID < len(RegionPalette) {
		return RegionPalette[regionID]
	}
	// Generate deterministic color for IDs outside palette
	return color.RGBA{
		uint8((regionID * 67) % 256),
		uint8((regionID * 113) % 256),
		uint8((regionID * 191) % 256),
		255,
	}
}

//
// Boundary marker colors
//

var BoundaryMarkerColors = []color.Color{
	EdgeDark,                      // 0: Default/internal
	color.RGBA{220, 50, 50, 255},  // 1: Red
	color.RGBA{50, 150, 220, 255}, // 2: Blue
	color.RGBA{50, 200, 80, 255},  // 3: Green
	color.RGBA{220, 180, 50, 255}, // 4: Yellow
	color.RGBA{180, 50, 220, 255}, // 5: Purple
	color.RGBA{220, 120, 50, 255}, // 6: Orange
	color.RGBA{50, 180, 180, 255}, // 7: Cyan
}

// GetBoundaryColor returns a color for a boundary marker
func GetBoundaryColor(marker int) color.Color {
	if marker >= 0 && marker < len(BoundaryMarkerColors) {
		return BoundaryMarkerColors[marker]
	}
	return EdgeDark
}

//
// Jet colormap (blue -> cyan -> yellow -> red) for solution fields
//

// Jet returns a color from the jet colormap for value in [0, 1]
func Jet(t float64) color.Color {
	// Clamp to [0, 1]
	t = math.Max(0, math.Min(1, t))

	var r, g, b float64

	if t < 0.25 {
		// Blue to cyan
		r = 0
		g = 4 * t
		b = 1
	} else if t < 0.5 {
		// Cyan to green
		r = 0
		g = 1
		b = 1 - 4*(t-0.25)
	} else if t < 0.75 {
		// Green to yellow
		r = 4 * (t - 0.5)
		g = 1
		b = 0
	} else {
		// Yellow to red
		r = 1
		g = 1 - 4*(t-0.75)
		b = 0
	}

	return color.RGBA{
		uint8(r * 255),
		uint8(g * 255),
		uint8(b * 255),
		255,
	}
}

// Viridis returns a color from the viridis colormap for value in [0, 1]
// Perceptually uniform and colorblind-friendly
func Viridis(t float64) color.Color {
	// Clamp to [0, 1]
	t = math.Max(0, math.Min(1, t))

	// Simplified viridis approximation
	r := math.Pow(t, 3)*0.3 + (1-math.Pow(1-t, 2))*0.5
	g := math.Pow(t, 2) * 0.8
	b := (1 - math.Pow(1-t, 3)) * 0.9

	return color.RGBA{
		uint8(r * 255),
		uint8(g * 255),
		uint8(b * 255),
		255,
	}
}

//
// Helper functions
//

// NewColorScale creates a ColorScale from RGBA values (0-255)
func NewColorScale(r, g, b, a uint8) ebiten.ColorScale {
	var cs ebiten.ColorScale
	cs.ScaleWithColor(color.RGBA{r, g, b, a})
	return cs
}

// ColorScaleFromColor creates a ColorScale from a color.Color
func ColorScaleFromColor(c color.Color) ebiten.ColorScale {
	var cs ebiten.ColorScale
	cs.ScaleWithColor(c)
	return cs
}
