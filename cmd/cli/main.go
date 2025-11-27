//go:build !wasm

package main

import (
	"fmt"
	"log"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/nativedisp"
	"github.com/hajimehoshi/ebiten/v2"
)

var header string = `
       _       __________________ 
      (_)___  / / ____/ ____/ __ \
     / / __ \/ / /   / /_  / / / /
    / / / / / / /___/ __/ / /_/ / 
 __/ /_/ /_/_/\____/_/   /_____/  
/___/                             `

func main() {
	fmt.Println(header)
	fmt.Println("\nSolving PCB heat transfer...")

	mesh := buildPCBMesh()

	ctx := setupPCBCase(mesh)

	T := solveHeatEquation(mesh, ctx)

	fmt.Printf("\nTemperature range: %.2f - %.2f K\n", minTemp(T), maxTemp(T))
	fmt.Println("Displaying solution...")

	viewer := nativedisp.NewSolutionViewer(mesh, T, 800, 600)
	ebiten.SetWindowSize(640, 480)
	ebiten.SetWindowTitle("jnlCFD viewer")

	if err := ebiten.RunGame(viewer); err != nil {
		log.Fatal(err)
	}
}

func buildPCBMesh() *geometry.Mesh {
	var db geometry.DomainBuilder

	// PCB substrate: 100mm x 100mm
	db.AddPolygon(geometry.MakeRectangle(0, 0, 100, 100, "pcb", "outer"))

	// 4 chips in a square pattern: 20mm x 20mm each
	// Spaced 50mm center-to-center
	chipSize := 20.0
	spacing := 50.0
	centerX, centerY := 50.0, 50.0

	// Chip positions (centered on PCB, 2x2 grid)
	chipPositions := []struct{ x, y float64 }{
		{centerX - spacing/2, centerY - spacing/2}, // Bottom-left
		{centerX + spacing/2, centerY - spacing/2}, // Bottom-right
		{centerX - spacing/2, centerY + spacing/2}, // Top-left
		{centerX + spacing/2, centerY + spacing/2}, // Top-right
	}

	for i, pos := range chipPositions {
		chipName := fmt.Sprintf("chip%d", i+1)
		x0 := pos.x - chipSize/2
		y0 := pos.y - chipSize/2
		db.AddPolygon(geometry.MakeRectangle(x0, y0, chipSize, chipSize,
			chipName, "chip_wall"))
	}

	domain, err := db.Build()
	if err != nil {
		log.Fatal(err)
	}

	// Mesh with reasonable refinement
	mesh, err := geometry.MeshDomain(domain, "pzq30a5") // q30 = max angle 30°, a5 = max area 5
	if err != nil {
		log.Fatal(err)
	}

	return mesh
}

func setupPCBCase(mesh *geometry.Mesh) *fvm.Context {
	ctx := fvm.NewContext(mesh)

	// Temperature field (initialize to ambient)
	ctx.AddUniformField("T", 300.0)

	// Thermal conductivity - region-specific
	ctx.AddRegionField("k", map[string]float64{
		"chip1": 150.0, // Silicon
		"chip2": 150.0,
		"chip3": 150.0,
		"chip4": 150.0,
		"pcb":   0.3, // FR4
	}, 0.3) // default to FR4

	// Heat generation - only in chips
	powerPerChip := 5.0     // Watts
	chipArea := 0.02 * 0.02 // 20mm x 20mm
	chipThickness := 0.001  // 1mm assumed
	qVolumetric := powerPerChip / (chipArea * chipThickness)

	ctx.AddRegionField("Q", map[string]float64{
		"chip1": qVolumetric,
		"chip2": qVolumetric,
		"chip3": qVolumetric,
		"chip4": qVolumetric,
	}, 0.0) // default to no heat generation

	return ctx
}

func solveHeatEquation(mesh *geometry.Mesh, ctx *fvm.Context) []float64 {
	eq := fvm.NewEquation(mesh)

	// Assemble
	eq.Zero()
	fvm.LaplacianOperator(eq, ctx, "T", fvm.FieldExpr(ctx, "k"), nil)

	mask := fvm.RegionsFromNames(ctx, "chip1", "chip2", "chip3", "chip4")
	fvm.LinearSourceOperator(eq, ctx, "T", fvm.FieldExpr(ctx, "Q"), nil, mask)
	fvm.ConvectionBC(eq, ctx, "outer", 10.0, 300.0)

	// Solve
	eq.UpdateCSRValues()
	csr := eq.GetCSR()

	solution := make([]float64, eq.NCells())
	for i := range solution {
		solution[i] = 300.0
	}

	solver := linalg.NewJacobiCG(eq.NCells(), 10000, 1e-6)
	err := solver.Solve(csr, eq.Source, solution)
	if err != nil {
		log.Fatalf("Solver failed: %v", err)
	}

	// Map back to global mesh
	T := ctx.Fields["T"]
	for localIdx := 0; localIdx < eq.NCells(); localIdx++ {
		globalIdx := eq.GetGlobalCellIndex(localIdx)
		T.Values[globalIdx] = solution[localIdx]
	}

	return T.Values
}

func minTemp(T []float64) float64 {
	min := T[0]
	for _, t := range T[1:] {
		if t < min {
			min = t
		}
	}
	return min
}

func maxTemp(T []float64) float64 {
	max := T[0]
	for _, t := range T[1:] {
		if t > max {
			max = t
		}
	}
	return max
}
