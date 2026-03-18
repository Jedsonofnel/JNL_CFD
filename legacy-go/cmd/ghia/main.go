package main

import (
	"fmt"
	"math"
	"os"
	"strconv"

	"jedn.dev/jnlcfd/fvm"
	"jedn.dev/jnlcfd/geometry"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: ghia <Re> [nCells]\n")
		fmt.Fprintf(os.Stderr, "  e.g. ghia 100 > ghia_re100.csv\n")
		os.Exit(1)
	}

	re, err := strconv.ParseFloat(os.Args[1], 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid Re: %s\n", os.Args[1])
		os.Exit(1)
	}

	nCells := 4000
	if len(os.Args) >= 3 {
		n, err := strconv.Atoi(os.Args[2])
		if err == nil {
			nCells = n
		}
	}

	fmt.Fprintf(os.Stderr, "Running LDC Re=%.0f with %d target cells...\n", re, nCells)
	result := fvm.CaseLidDrivenCavity(nCells, re)
	fmt.Fprintf(os.Stderr, "Converged in %d iterations, final res = %.2e\n",
		result.Iterations, result.FinalRes)

	mesh := result.Mesh

	// Sample Ux along vertical centreline (x=0.5)
	uxProfile := sampleVerticalLine(mesh, result.Ux, 0.5, 200)

	// Sample Uy along horizontal centreline (y=0.5)
	uyProfile := sampleHorizontalLine(mesh, result.Uy, 0.5, 200)

	// Find matching Ghia data
	var ghia *GhiaData
	for _, g := range GhiaBenchmark() {
		if g.Re == int(re) {
			g := g
			ghia = &g
			break
		}
	}

	// Output CSV: two blocks separated by blank lines for gnuplot
	fmt.Println("# Lid-driven cavity centreline profiles")
	fmt.Printf("# Re = %.0f, mesh cells = %d\n", re, len(mesh.Centroids))
	fmt.Println()

	// Block 1: Ux along vertical centreline
	fmt.Println("# y, Ux_sim")
	for _, p := range uxProfile {
		fmt.Printf("%.6f, %.6f\n", p.coord, p.value)
	}
	fmt.Println()
	fmt.Println()

	// Block 2: Ghia Ux reference
	fmt.Println("# y, Ux_ghia")
	if ghia != nil {
		for _, g := range ghia.UxVertical {
			fmt.Printf("%.6f, %.6f\n", g.Coord, g.Value)
		}
	}
	fmt.Println()
	fmt.Println()

	// Block 3: Uy along horizontal centreline
	fmt.Println("# x, Uy_sim")
	for _, p := range uyProfile {
		fmt.Printf("%.6f, %.6f\n", p.coord, p.value)
	}
	fmt.Println()
	fmt.Println()

	// Block 4: Ghia Uy reference
	fmt.Println("# x, Uy_ghia")
	if ghia != nil {
		for _, g := range ghia.UyHorizontal {
			fmt.Printf("%.6f, %.6f\n", g.Coord, g.Value)
		}
	}
}

type sample struct {
	coord float64
	value float64
}

// sampleVerticalLine samples a field along x=xTarget at nPoints evenly
// spaced y values, using nearest-cell lookup.
func sampleVerticalLine(
	mesh *geometry.Mesh, field []float64, xTarget float64, nPoints int,
) []sample {
	samples := make([]sample, nPoints)
	for i := range nPoints {
		y := float64(i) / float64(nPoints-1)
		idx := nearestCell(mesh.Centroids, xTarget, y)
		samples[i] = sample{coord: y, value: field[idx]}
	}
	return samples
}

// sampleHorizontalLine samples a field along y=yTarget at nPoints evenly
// spaced x values, using nearest-cell lookup.
func sampleHorizontalLine(
	mesh *geometry.Mesh, field []float64, yTarget float64, nPoints int,
) []sample {
	samples := make([]sample, nPoints)
	for i := range nPoints {
		x := float64(i) / float64(nPoints-1)
		idx := nearestCell(mesh.Centroids, x, yTarget)
		samples[i] = sample{coord: x, value: field[idx]}
	}
	return samples
}

func nearestCell(centroids []geometry.Vec2, x, y float64) int {
	bestIdx := 0
	bestDist := math.MaxFloat64
	for i, c := range centroids {
		dx := c.X - x
		dy := c.Y - y
		d := dx*dx + dy*dy
		if d < bestDist {
			bestDist = d
			bestIdx = i
		}
	}
	return bestIdx
}
