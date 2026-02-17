package main

import (
	"flag"
	"fmt"
	"math"
	"os"

	"jedn.dev/jnlcfd/fvm"
	"jedn.dev/jnlcfd/geometry/output"
)

//
// bin/example is for creating plots of test cases
//

var cases = map[string]string{
	"poiseuille":            "Pressure-driven channel flow (SIMPLE with convection)",
	"couette":               "Shear-driven flow with moving top wall (SIMPLE with convection)",
	"poiseuille-simplified": "Pressure-driven flow (pure diffusion, no pressure coupling)",
	"couette-simplified":    "Shear-driven flow (pure diffusion, no pressure coupling)",
}

func main() {
	nCells := flag.Int("n", 400, "target number of mesh cells")
	gamma := flag.Float64("gamma", 1.0, "dynamic viscosity")
	rho := flag.Float64("rho", 1.0, "density")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: example [flags] <case>\n\nCases:\n")
		for name, desc := range cases {
			fmt.Fprintf(os.Stderr, "  %-24s %s\n", name, desc)
		}
		fmt.Fprintf(os.Stderr, "\nFlags:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	caseName := flag.Arg(0)
	if caseName == "" {
		caseName = "poiseuille"
	}

	if _, ok := cases[caseName]; !ok {
		fmt.Fprintf(os.Stderr, "Unknown case: %q\n", caseName)
		flag.Usage()
		os.Exit(1)
	}

	switch caseName {
	case "poiseuille":
		runPoiseuilleSIMPLE(*nCells, *gamma, *rho)
	case "poiseuille-simplified":
		runPoiseuilleSimplified(*nCells, *gamma)
	case "couette":
		runCouetteSimplified(*nCells, *gamma)
	}
}

func runPoiseuilleSIMPLE(nCells int, gamma, rho float64) {
	result := fvm.CasePoiseuilleSIMPLE(nCells, gamma, rho)
	LogSIMPLEResult(result, "Poiseuille (SIMPLE)")

	// dpdx = (0 - 1) / 4 = -0.25 for the 4:1 channel with p_in=1, p_out=0
	dpdx := -0.25
	H := 1.0
	maxErr := fvm.PoiseuilleMaxError(result.Ux, result.Mesh.Centroids, 2.0, 0.2, H, dpdx, gamma)
	fmt.Fprintf(os.Stderr, "Max velocity error at x=2: %.4e (expected max Ux = %.4e)\n",
		maxErr, fvm.PoiseuilleAnalytical(0.5, H, dpdx, gamma))

	analytical := make([]float64, len(result.Mesh.Centroids))
	err := make([]float64, len(result.Mesh.Centroids))
	for i, c := range result.Mesh.Centroids {
		analytical[i] = fvm.PoiseuilleAnalytical(c.Y, H, dpdx, gamma)
		err[i] = result.Ux[i] - analytical[i]
	}

	output.WriteVTK(os.Stdout, result.Mesh,
		output.VTKField{Name: "Ux", Values: result.Ux},
		output.VTKField{Name: "Uy", Values: result.Uy},
		output.VTKField{Name: "p", Values: result.P},
		output.VTKField{Name: "Ux_analytical", Values: analytical},
		output.VTKField{Name: "error", Values: err},
	)
}

func runPoiseuilleSimplified(nCells int, gamma float64) {
	dpdx := -10.0
	Ux, mesh, _ := fvm.CasePoiseuille(nCells, gamma, dpdx)

	analytical := make([]float64, len(mesh.Centroids))
	err := make([]float64, len(mesh.Centroids))
	H := 1.0
	maxErr := 0.0
	for i, c := range mesh.Centroids {
		analytical[i] = fvm.PoiseuilleAnalytical(c.Y, H, dpdx, gamma)
		err[i] = Ux[i] - analytical[i]
		maxErr = max(maxErr, math.Abs(err[i]))
	}
	fmt.Fprintf(os.Stderr, "Poiseuille (simplified): max error = %.4e\n", maxErr)

	output.WriteVTK(os.Stdout, mesh,
		output.VTKField{Name: "Ux", Values: Ux},
		output.VTKField{Name: "Ux_analytical", Values: analytical},
		output.VTKField{Name: "error", Values: err},
	)
}

func runCouetteSimplified(nCells int, gamma float64) {
	Uwall := 1.0
	Ux, mesh, _ := fvm.CaseCouette(nCells, gamma, Uwall)

	analytical := make([]float64, len(mesh.Centroids))
	err := make([]float64, len(mesh.Centroids))
	maxErr := 0.0
	for i, c := range mesh.Centroids {
		analytical[i] = Uwall * c.Y
		err[i] = Ux[i] - analytical[i]
		maxErr = max(maxErr, math.Abs(err[i]))
	}
	fmt.Fprintf(os.Stderr, "Couette (simplified): max error = %.4e\n", maxErr)

	output.WriteVTK(os.Stdout, mesh,
		output.VTKField{Name: "Ux", Values: Ux},
		output.VTKField{Name: "Ux_analytical", Values: analytical},
		output.VTKField{Name: "error", Values: err},
	)
}

//
// Helpers
//

func LogSIMPLEResult(result fvm.SIMPLEResult, name string) {
	fmt.Fprintf(
		os.Stderr, "%s: converged in %d iterations, final residual = %.2e\n",
		name, result.Iterations, result.FinalRes,
	)
}
