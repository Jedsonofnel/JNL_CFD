package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"os"
	"strconv"

	"jedn.dev/jnlcfd/fvm"
	"jedn.dev/jnlcfd/geometry"
)

const (
	NUM_CELLS = 10
	GAMMA     = 1
)

func main() {
	mesh := geometry.MakeRectangular1DMesh(NUM_CELLS)
	fmt.Printf("%v\n", mesh.BoundaryNames)

	for i, conn := range mesh.Connections {
		fmt.Printf("conn %d: %v\n", i, conn)
	}

	field := make([]float64, NUM_CELLS)
	sys := fvm.NewFVSystem(mesh)

	fvm.LaplacianConstant(sys, mesh, GAMMA)

	fvm.DirichletConstBC(sys, mesh, 0, "west")
	fvm.DirichletConstBC(sys, mesh, 100, "east")

	// implicit when no BC is specified BUT good to be explicit here
	fvm.NeumannConstBC(sys, mesh, 0, "south")
	fvm.NeumannConstBC(sys, mesh, 0, "north")

	sys.Solve(field, 1e-6, 100)

	Write1DToCSV(os.Stdout, mesh, field)
}

//
// Output helpers
//

// Writes a CSV to the output writer supplied
func Write1DToCSV(
	out io.Writer,
	mesh *geometry.Mesh,
	phi []float64,
) {
	headers := []string{"x", "phi"}

	w := csv.NewWriter(out)
	err := w.Write(headers)
	if err != nil {
		log.Fatalln("error writing record to csv:", err)
	}

	for i := range mesh.Centroids {
		record := []string{
			strconv.FormatFloat(mesh.Centroids[i].X, 'g', -1, 64),
			strconv.FormatFloat(phi[i], 'g', -1, 64),
		}

		err := w.Write(record)
		if err != nil {
			log.Fatalln("error writing record to csv:", err)
		}
	}

	w.Flush()

	if err := w.Error(); err != nil {
		log.Fatal(err)
	}
}
