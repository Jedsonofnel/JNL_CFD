package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"

	"jedn.dev/jnlcfd/fvm"
	"jedn.dev/jnlcfd/geometry"
	"jedn.dev/jnlcfd/geometry/output"
)

//
// bin/example is for creating plots of test cases
//

const (
	DEFAULT_CASE = "poiseuille" // others are "convdiff" and "lineardiff"
)

func main() {
	flag.Parse()
	args := flag.Args()
	if len(args) > 1 {
		fmt.Fprintf(os.Stderr, "Too many arguments, got %d, expected 1 at most\n", len(args))
		os.Exit(1) // an error!
	}

	if len(args) == 0 { // ie if nothing then use default case
		poiseuille(1, 1)
		os.Exit(0)
	}

	fmt.Fprintf(os.Stderr, "TODO: implement specifying named case\n")
	os.Exit(1)
}

func couette(rho, gamma float64) {
	Uwall := 1.0
	Ux, mesh, _ := fvm.CaseCouette(3200, gamma, Uwall)

	analytical := make([]float64, len(mesh.Centroids))
	err := make([]float64, len(mesh.Centroids))
	for i, pt := range mesh.Centroids {
		analytical[i] = pt.Y
		err[i] = Ux[i] - analytical[i]
	}

	output.WriteVTK(os.Stdout, mesh,
		output.VTKField{Name: "Ux", Values: Ux},
		output.VTKField{Name: "analytical", Values: analytical},
		output.VTKField{Name: "error", Values: err},
	)
}

func poiseuille(rho, gamma float64) {
	pYgrad := -10.0
	Ux, mesh, _ := fvm.CaseCouette(3200, gamma, pYgrad)

	output.WriteVTK(os.Stdout, mesh,
		output.VTKField{Name: "Ux", Values: Ux},
	)
}

func convdiff(nCells int, gamma, rho, velocity float64) {
	mesh := geometry.MakeSimple1DMesh(nCells)

	// Velocity field
	Ux := make([]float64, nCells)
	for i := range Ux {
		Ux[i] = velocity
	}
	// Uy := make([]float64, NUM_CELLS) // zero

	UxFace := make([]float64, len(mesh.Connections))
	UyFace := make([]float64, len(mesh.Connections))
	fvm.FaceInterpCDS(mesh, Ux, UxFace)
	// UyFace stays zero

	Unormal := make([]float64, len(mesh.Connections))
	fvm.FaceNormalComponent(mesh, UxFace, UyFace, Unormal)

	// CDS solution
	phiCDS := make([]float64, nCells)
	sysCDS := fvm.NewFVSystem(mesh)
	fvm.LaplacianConst(sysCDS, mesh, gamma, nil, nil)
	fvm.DivConstCDS(sysCDS, mesh, rho, Unormal)
	fvm.DirichletConstBC(sysCDS, mesh, 0, "west")
	fvm.DirichletConstBC(sysCDS, mesh, 100, "east")
	sysCDS.SolveCG(phiCDS, 1e-6, 100)

	fmt.Fprintf(os.Stderr, "CDS - Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e\n",
		sysCDS.DiagonalDominanceRatio(), sysCDS.MaxAsymmetry(), sysCDS.ResidualNorm(phiCDS))

	// UDS solution
	phiUDS := make([]float64, nCells)
	sysUDS := fvm.NewFVSystem(mesh)
	fvm.LaplacianConst(sysUDS, mesh, gamma, nil, nil)
	fvm.DivConstUDS(sysUDS, mesh, rho, Unormal)
	fvm.DirichletConstBC(sysUDS, mesh, 0, "west")
	fvm.DirichletConstBC(sysUDS, mesh, 100, "east")
	sysUDS.SolveCG(phiUDS, 1e-6, 100)

	fmt.Fprintf(os.Stderr, "UDS - Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e\n",
		sysUDS.DiagonalDominanceRatio(), sysUDS.MaxAsymmetry(), sysUDS.ResidualNorm(phiUDS))

	// Analytical
	phiAnalytical := make([]float64, nCells)
	for i, c := range mesh.Centroids {
		phiAnalytical[i] = analytical1D(c.X, 1.0, velocity, rho, gamma, 0, 100)
	}

	WriteComparisonCSV(os.Stdout, mesh, phiCDS, phiUDS, phiAnalytical)
}

func analytical1D(x, length, ux, rho, gamma, phi0, phiL float64) float64 {
	Pe := rho * ux * length / gamma
	if math.Abs(Pe) < 1e-10 {
		return phi0 + (x/length)*(phiL-phi0)
	}
	coeff := (math.Exp(Pe*x/length) - 1) / (math.Exp(Pe) - 1)
	return phi0 + coeff*(phiL-phi0)
}

func WriteComparisonCSV(out io.Writer, mesh *geometry.Mesh, phiCDS, phiUDS, phiAnalytical []float64) {
	w := csv.NewWriter(out)
	w.Write([]string{"x", "phi_CDS", "phi_UDS", "phi_analytical"})
	w.Write([]string{"0", "0", "0", "0"})

	for i := range mesh.Centroids {
		w.Write([]string{
			strconv.FormatFloat(mesh.Centroids[i].X, 'g', -1, 64),
			strconv.FormatFloat(phiCDS[i], 'g', -1, 64),
			strconv.FormatFloat(phiUDS[i], 'g', -1, 64),
			strconv.FormatFloat(phiAnalytical[i], 'g', -1, 64),
		})
	}
	w.Write([]string{"1", "100", "100", "100"})
	w.Flush()
}

func minMax(f []float64) (float64, float64) {
	mn, mx := f[0], f[0]
	for _, v := range f {
		if v < mn {
			mn = v
		}
		if v > mx {
			mx = v
		}
	}
	return mn, mx
}
