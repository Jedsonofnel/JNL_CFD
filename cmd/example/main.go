package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"

	"jedn.dev/jnlcfd/fvm"
	"jedn.dev/jnlcfd/geometry"
)

const (
	NUM_CELLS = 10
	GAMMA     = 1.0
	RHO       = 1.0
	VELOCITY  = 1.0
)

func main() {
	mesh := geometry.MakeRectangular1DMesh(NUM_CELLS)

	// Velocity field
	Ux := make([]float64, NUM_CELLS)
	for i := range Ux {
		Ux[i] = VELOCITY
	}
	// Uy := make([]float64, NUM_CELLS) // zero

	UxFace := make([]float64, len(mesh.Connections))
	UyFace := make([]float64, len(mesh.Connections))
	fvm.FaceInterpCDS(mesh, Ux, UxFace)
	// UyFace stays zero

	Unormal := make([]float64, len(mesh.Connections))
	fvm.FaceNormalComponent(mesh, UxFace, UyFace, Unormal)

	// Debug: print face normals and Unormal at boundaries
	fmt.Fprintln(os.Stderr, "=== Boundary face debug ===")
	for marker, name := range mesh.BoundaryNames {
		fmt.Fprintf(os.Stderr, "Boundary %q (marker %d):\n", name, marker)
		for i, conn := range mesh.Connections {
			if conn.Neighbour == int32(-marker) {
				n := mesh.FaceNormals[i]
				fmt.Fprintf(os.Stderr, "  conn %d: normal=(%.2f, %.2f), Unormal=%.2f\n",
					i, n.X, n.Y, Unormal[i])
			}
		}
	}
	fmt.Fprintln(os.Stderr)

	fmt.Fprintln(os.Stderr, "=== Internal face debug ===")
	for i, conn := range mesh.Connections {
		if conn.Neighbour >= 0 {
			n := mesh.FaceNormals[i]
			w := mesh.InterpWeights[i]
			fmt.Fprintf(os.Stderr, "conn %d: owner=%d→neighbour=%d, normal=(%.2f, %.2f), Unormal=%.2f, weight=%.3f\n",
				i, conn.Owner, conn.Neighbour, n.X, n.Y, Unormal[i], w)
		}
	}

	// CDS solution
	phiCDS := make([]float64, NUM_CELLS)
	sysCDS := fvm.NewFVSystem(mesh)
	fvm.LaplacianConst(sysCDS, mesh, GAMMA)
	fvm.DivConstCDS(sysCDS, mesh, RHO, Unormal)
	fvm.DirichletConstBC(sysCDS, mesh, 0, "west")
	fvm.DirichletConstBC(sysCDS, mesh, 100, "east")
	sysCDS.Solve(phiCDS, 1e-6, 100)

	fmt.Fprintf(os.Stderr, "CDS - Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e\n",
		sysCDS.DiagonalDominanceRatio(), sysCDS.MaxAsymmetry(), sysCDS.ResidualNorm(phiCDS))

	// UDS solution
	phiUDS := make([]float64, NUM_CELLS)
	sysUDS := fvm.NewFVSystem(mesh)
	fvm.LaplacianConst(sysUDS, mesh, GAMMA)
	fvm.DivConstUDS(sysUDS, mesh, RHO, Unormal)
	fvm.DirichletConstBC(sysUDS, mesh, 0, "west")
	fvm.DirichletConstBC(sysUDS, mesh, 100, "east")
	sysUDS.Solve(phiUDS, 1e-6, 100)

	fmt.Fprintf(os.Stderr, "UDS - Diag dominance: %.3f, Asymmetry: %.2e, Residual: %.2e\n",
		sysUDS.DiagonalDominanceRatio(), sysUDS.MaxAsymmetry(), sysUDS.ResidualNorm(phiUDS))

	// Analytical
	phiAnalytical := make([]float64, NUM_CELLS)
	for i, c := range mesh.Centroids {
		phiAnalytical[i] = analytical1D(c.X, 1.0, VELOCITY, RHO, GAMMA, 0, 100)
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
