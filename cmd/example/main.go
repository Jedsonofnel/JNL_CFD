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
	"poiseuille-simplified": "Pressure-driven flow (pure diffusion, no pressure coupling)",
	"couette":               "Shear-driven flow (pure diffusion, no pressure coupling)",
	"cavity":                "Lid-driven cavity flow (SIMPLE with convection)",
	"developing-poiseuille": "Developing channel flow from a uniform inlet",
	"cht-heated-block":      "Conjugate heat transfer over a heated block (SIMPLE_CHT)",
	"forced-plate":          "Decoupled forced convection over a heated flat plate",
}

func main() {
	nCells := flag.Int("n", 400, "target number of mesh cells")
	gamma := flag.Float64("gamma", 1.0, "dynamic viscosity")
	rho := flag.Float64("rho", 1.0, "density")
	re := flag.Float64("re", 100, "Reynolds number (cavity only)")
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
	case "cavity":
		runCavity(*nCells, *re)
	case "developing-poiseuille":
		runDevelopingPoiseuille(*nCells, *gamma, *rho)
	case "cht-heated-block":
		runHeatedBlockCHT(*nCells)
	case "forced-plate":
		runForcedConvectionPlate(*nCells)
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
		output.Scalar{Name: "Ux", Values: result.Ux},
		output.Scalar{Name: "Uy", Values: result.Uy},
		output.Scalar{Name: "p", Values: result.P},
		output.Scalar{Name: "Ux_analytical", Values: analytical},
		output.Scalar{Name: "error", Values: err},
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
		output.Scalar{Name: "Ux", Values: Ux},
		output.Scalar{Name: "Ux_analytical", Values: analytical},
		output.Scalar{Name: "error", Values: err},
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
		output.Scalar{Name: "Ux", Values: Ux},
		output.Scalar{Name: "Ux_analytical", Values: analytical},
		output.Scalar{Name: "error", Values: err},
	)
}

func runCavity(nCells int, Re float64) {
	result := fvm.CaseLidDrivenCavity(nCells, Re)
	LogSIMPLEResult(result, fmt.Sprintf("Lid-driven cavity (Re=%.0f)", Re))

	mesh := result.Mesh
	nConns := len(mesh.Connections)
	nCells = len(mesh.Centroids)

	// Velocity magnitude
	Umag := make([]float64, nCells)
	for i := range Umag {
		Umag[i] = math.Sqrt(result.Ux[i]*result.Ux[i] + result.Uy[i]*result.Uy[i])
	}

	// Face interpolation with BCs for accurate boundary gradients
	UxFace := make([]float64, nConns)
	UyFace := make([]float64, nConns)

	fvm.FaceInterpCDS(mesh, result.Ux, UxFace)
	fvm.DirichletFaceValuesConst(mesh, UxFace, "north", 1.0)
	fvm.DirichletFaceValuesConst(mesh, UxFace, "south", 0)
	fvm.DirichletFaceValuesConst(mesh, UxFace, "east", 0)
	fvm.DirichletFaceValuesConst(mesh, UxFace, "west", 0)

	fvm.FaceInterpCDS(mesh, result.Uy, UyFace)
	fvm.DirichletFaceValuesConst(mesh, UyFace, "north", 0)
	fvm.DirichletFaceValuesConst(mesh, UyFace, "south", 0)
	fvm.DirichletFaceValuesConst(mesh, UyFace, "east", 0)
	fvm.DirichletFaceValuesConst(mesh, UyFace, "west", 0)

	// Green-Gauss gradients
	gradUxy := make([]float64, nCells) // ∂Ux/∂y
	gradUyx := make([]float64, nCells) // ∂Uy/∂x
	unused := make([]float64, nCells)

	fvm.GreenGaussGradient(mesh, UxFace, unused, gradUxy) // only need ∂Ux/∂y
	fvm.GreenGaussGradient(mesh, UyFace, gradUyx, unused) // only need ∂Uy/∂x

	// Vorticity: ω = ∂Uy/∂x - ∂Ux/∂y
	omega := make([]float64, nCells)
	fvm.Vorticity2D(gradUyx, gradUxy, omega)

	output.WriteVTK(os.Stdout, mesh,
		output.Scalar{Name: "p", Values: result.P},
		output.Scalar{Name: "Umag", Values: Umag},
		output.Scalar{Name: "vorticity", Values: omega},
		output.Vector{Name: "U", X: result.Ux, Y: result.Uy},
	)
}

func runDevelopingPoiseuille(nCells int, gamma, rho float64) {
	Uin := 1.0
	result := fvm.CaseDevelopingPoiseuille(nCells, gamma, rho, Uin)
	LogSIMPLEResult(result, "Developing Poiseuille")

	// For a developed profile, mass conservation dictates U_max = 1.5 * U_avg in 2D
	H := 1.0
	// Umax_expected := 1.5 * Uin

	analytical := make([]float64, len(result.Mesh.Centroids))
	for i, c := range result.Mesh.Centroids {
		// Parabolic profile equation: U(y) = 6 * U_avg * (y/H) * (1 - y/H)
		analytical[i] = 6.0 * Uin * (c.Y / H) * (1.0 - c.Y/H)
	}

	output.WriteVTK(os.Stdout, result.Mesh,
		output.Scalar{Name: "Ux", Values: result.Ux},
		output.Scalar{Name: "Uy", Values: result.Uy},
		output.Scalar{Name: "p", Values: result.P},
		output.Scalar{Name: "Ux_developed_analytical", Values: analytical},
	)
}

func runForcedConvectionPlate(nCells int) {
	Uin := 1.0
	heatFlux := 5000.0 // W/m^2 injected from the bottom plate

	fmt.Fprintf(os.Stderr, "Running Forced Convection over Flat Plate (%d cells)...\n", nCells)

	result := fvm.CaseForcedConvectionPlate(nCells, Uin, heatFlux)

	fmt.Fprintf(os.Stderr, "Hydrodynamics converged in %d iterations.\n", result.Iterations)

	output.WriteVTK(os.Stdout, result.Mesh,
		output.Scalar{Name: "p", Values: result.P},
		output.Scalar{Name: "T", Values: result.T},
		output.Vector{Name: "U", X: result.Ux, Y: result.Uy},
	)
}

func runHeatedBlockCHT(nCells int) {
	Uin := 1.0
	result := fvm.CaseHeatedBlockCHT(nCells, Uin)
	fmt.Fprintf(os.Stderr, "CHT Heated Block: converged in %d iterations, final residual = %.2e\n",
		result.Iterations, result.FinalRes)

	output.WriteVTK(os.Stdout, result.Mesh,
		output.Scalar{Name: "p", Values: result.P},
		output.Scalar{Name: "T", Values: result.T},
		output.Vector{Name: "U", X: result.Ux, Y: result.Uy},
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
