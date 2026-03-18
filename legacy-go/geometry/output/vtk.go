package output

import (
	"fmt"
	"io"

	"jedn.dev/jnlcfd/geometry"
)

// VTKField is implemented by any type that can write itself into a VTK
// CELL_DATA section. The Write method is responsible for emitting the
// correct VTK header (SCALARS, VECTORS, TENSORS, etc.) and data lines.
type VTKField interface {
	Write(w io.Writer)
}

// Scalar writes a single-component cell field.
//
//	SCALARS <name> float 1
//	LOOKUP_TABLE default
//	<value per cell>
type Scalar struct {
	Name   string
	Values []float64
}

func (s Scalar) Write(w io.Writer) {
	fmt.Fprintf(w, "SCALARS %s float 1\n", s.Name)
	fmt.Fprintln(w, "LOOKUP_TABLE default")
	for _, v := range s.Values {
		fmt.Fprintf(w, "%e\n", v)
	}
}

// Vector writes a 3-component cell field (Z is always 0 for 2D).
//
//	VECTORS <name> float
//	<x y 0> per cell
type Vector struct {
	Name string
	X, Y []float64
}

func (v Vector) Write(w io.Writer) {
	fmt.Fprintf(w, "VECTORS %s float\n", v.Name)
	for i := range v.X {
		fmt.Fprintf(w, "%e %e 0\n", v.X[i], v.Y[i])
	}
}

// WriteVTK writes an unstructured grid VTK file with any combination of
// scalar, vector (or future tensor) fields.
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
		for _, f := range fields {
			f.Write(w)
		}
	}
}
