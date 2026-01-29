package output

import (
	"fmt"
	"io"

	"jedn.dev/jnlcfd/geometry"
)

type VTKField struct {
	Name   string
	Values []float64
}

func WriteVTK(w io.Writer, m *geometry.Mesh, fields ...VTKField) {
	nCells := len(m.Centroids)
	nVerts := len(m.Vertices)

	fmt.Fprintln(w, "# vtk DataFile Version 3.0")
	fmt.Fprintln(w, "CFD Output")
	fmt.Fprintln(w, "ASCII")
	fmt.Fprintln(w, "DATASET UNSTRUCTURED_GRID")

	fmt.Fprintf(w, "POINTS %d float\n", nVerts)
	for _, v := range m.Vertices {
		fmt.Fprintf(w, "%f %f 0\n", v.X, v.Y)
	}

	// Count total size for CELLS line
	totalSize := 0
	for i := 0; i < nCells; i++ {
		nv := m.FaceStarts[i+1] - m.FaceStarts[i]
		totalSize += 1 + nv
	}

	fmt.Fprintf(w, "CELLS %d %d\n", nCells, totalSize)
	for i := 0; i < nCells; i++ {
		start := m.FaceStarts[i]
		end := m.FaceStarts[i+1]
		fmt.Fprintf(w, "%d", end-start)
		for j := start; j < end; j++ {
			fmt.Fprintf(w, " %d", m.VertexIndices[j])
		}
		fmt.Fprintln(w)
	}

	fmt.Fprintf(w, "CELL_TYPES %d\n", nCells)
	for i := 0; i < nCells; i++ {
		nv := m.FaceStarts[i+1] - m.FaceStarts[i]
		switch nv {
		case 3:
			fmt.Fprintln(w, "5") // VTK_TRIANGLE
		case 4:
			fmt.Fprintln(w, "9") // VTK_QUAD
		default:
			fmt.Fprintln(w, "7") // VTK_POLYGON
		}
	}

	if len(fields) > 0 {
		fmt.Fprintf(w, "CELL_DATA %d\n", nCells)
		for _, field := range fields {
			fmt.Fprintf(w, "SCALARS %s float 1\n", field.Name)
			fmt.Fprintln(w, "LOOKUP_TABLE default")
			for _, v := range field.Values {
				fmt.Fprintf(w, "%e\n", v)
			}
		}
	}
}
