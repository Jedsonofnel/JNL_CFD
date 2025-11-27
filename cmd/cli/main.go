//go:build !wasm

package main

import (
	"errors"
	"fmt"
	"log"
	"os"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/nativedisp"

	jnl "jedn.dev/jnlisp"
	"jedn.dev/jnlisp/cli"
)

var header string = `
       _       __________________ 
      (_)___  / / ____/ ____/ __ \
     / / __ \/ / /   / /_  / / / /
    / / / / / / /___/ __/ / /_/ / 
 __/ /_/ /_/_/\____/_/   /_____/  
/___/                             `

var runtime *jnl.Runtime

func init() {
	lispIO := jnl.IO{
		FS:     os.DirFS("."),
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
	}

	runtime = jnl.NewRuntime(lispIO)
	runtime.RegisterNamespace(geometry.NS)
	runtime.RegisterNamespace(nativedisp.NS)
}

func main() {
	fmt.Println(header)
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	switch len(os.Args[1:]) {
	case 0:
		return startREPL()
	}
	return errors.New("jnlcfd does not expect any args")
}

func startREPL() error {
	repl := cli.NewREPL(runtime, "jnlCFD REPL")
	repl.SetNamespace("jnlcfd")

	var err error
	err = repl.LoadAndRefer(geometry.NS, "")
	err = repl.LoadAndRefer(nativedisp.NS, "")
	if err != nil {
		return jnl.FormatError(err)
	}

	if err := repl.RawTerminal(); err != nil {
		return repl.SimpleTerminal()
	}
	return nil
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

	pcbThickness := 0.002                      // 2mm
	surfaceAreaPerVolume := 2.0 / pcbThickness // top + bottom surfaces

	h := 10.0     // W/m²K convection coefficient
	Tamb := 300.0 // K

	// Volumetric convection coefficient: A*h
	ctx.AddConstantField("Ah", surfaceAreaPerVolume*h)
	ctx.AddConstantField("T_amb", Tamb)

	return ctx
}

func solveHeatEquation(mesh *geometry.Mesh, ctx *fvm.Context) []float64 {
	eq := fvm.NewEquation(mesh)

	// Assemble
	eq.Zero()
	fvm.LaplacianOperator(eq, ctx, "T", fvm.FieldExpr(ctx, "k"), nil)

	mask := fvm.RegionsFromNames(ctx, "chip1", "chip2", "chip3", "chip4")
	fvm.LinearSourceOperator(eq, ctx, "T", fvm.FieldExpr(ctx, "Q"), nil, mask)

	AhExpr := fvm.FieldExpr(ctx, "Ah")
	TambExpr := fvm.FieldExpr(ctx, "T_amb")

	// Su = Ah * Tamb (explicit source)
	SuExpr := fvm.MulExpr(AhExpr, TambExpr)
	// Sp = -Ah (implicit, negative for stability)
	SpExpr := fvm.MulExpr(fvm.ConstExpr(-1.0), AhExpr)

	fvm.LinearSourceOperator(eq, ctx, "T", SuExpr, SpExpr, nil)

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
