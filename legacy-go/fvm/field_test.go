package fvm

import (
	"math"
	"testing"

	"jedn.dev/jnlcfd/geometry"
)

//
// Face interpolation
//

func TestFaceInterpolation(t *testing.T) {
	mesh := geometry.MakeSimple1DMesh(10)

	// Linear profile: φ = 100x (exact for CDS)
	field := make([]float64, 10)
	for i, c := range mesh.Centroids {
		field[i] = 100 * c.X
	}

	faceField := make([]float64, len(mesh.Connections))
	FaceInterpCDS(mesh, field, faceField)
	DirichletFaceValuesConst(mesh, faceField, "west", 0)
	DirichletFaceValuesConst(mesh, faceField, "east", 100)

	for i, conn := range mesh.Connections {
		var want float64
		if conn.Neighbour >= 0 {
			want = 100 * mesh.FaceCentroids[i].X // linear field → exact interp
		} else {
			switch mesh.BoundaryNames[int(-conn.Neighbour)] {
			case "west":
				want = 0
			case "east":
				want = 100
			default: // north/south: zero flux → face = owner
				want = field[conn.Owner]
			}
		}
		if !floatsEqual(faceField[i], want, FLOAT_TOL) {
			t.Errorf("face %d: got %v, want %v", i, faceField[i], want)
		}
	}
}

//
// Gradient reconstruction
//

func TestGreenGaussGradient(t *testing.T) {
	mesh := geometry.MakeSimple1DMesh(10)

	// Linear profile: φ = 100x → ∇φ = (100, 0)
	field := make([]float64, 10)
	for i, c := range mesh.Centroids {
		field[i] = 100 * c.X
	}

	faceField := make([]float64, len(mesh.Connections))
	gradX := make([]float64, 10)
	gradY := make([]float64, 10)

	FaceInterpCDS(mesh, field, faceField)
	DirichletFaceValuesConst(mesh, faceField, "west", 0)
	DirichletFaceValuesConst(mesh, faceField, "east", 100)

	GreenGaussGradient(mesh, faceField, gradX, gradY)

	for i := range field {
		if !floatsEqual(gradX[i], 100, FLOAT_TOL) {
			t.Errorf("cell %d: gradX = %v, want 100", i, gradX[i])
		}
		if !floatsEqual(gradY[i], 0, FLOAT_TOL) {
			t.Errorf("cell %d: gradY = %v, want 0", i, gradY[i])
		}
	}
}

func TestGreenGaussGradientDiagonal(t *testing.T) {
	mesh := geometry.MakeRectangular2DStrip(10)

	// φ = 3x + 7y → ∇φ = (3, 7)
	field := make([]float64, 10)
	for i, c := range mesh.Centroids {
		field[i] = 3*c.X + 7*c.Y
	}

	faceField := make([]float64, len(mesh.Connections))
	gradX := make([]float64, 10)
	gradY := make([]float64, 10)

	// All boundaries: extrapolate from linear field
	FaceInterpCDS(mesh, field, faceField)
	for i, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			fc := mesh.FaceCentroids[i]
			faceField[i] = 3*fc.X + 7*fc.Y
		}
	}

	GreenGaussGradient(mesh, faceField, gradX, gradY)

	for i := range field {
		if !floatsEqual(gradX[i], 3, FLOAT_TOL) {
			t.Errorf("cell %d: gradX = %v, want 3", i, gradX[i])
		}
		if !floatsEqual(gradY[i], 7, FLOAT_TOL) {
			t.Errorf("cell %d: gradY = %v, want 7", i, gradY[i])
		}
	}
}

func TestGreenGaussTriangular(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 1, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 200, 30)

	nCells := len(mesh.Centroids)

	// Linear field: φ = 3x + 7y → ∇φ = (3, 7) exactly
	field := make([]float64, nCells)
	for i, c := range mesh.Centroids {
		field[i] = 3*c.X + 7*c.Y
	}

	faceField := make([]float64, len(mesh.Connections))
	gradX := make([]float64, nCells)
	gradY := make([]float64, nCells)

	// Set face values exactly (this isolates gradient from interpolation)
	for i, conn := range mesh.Connections {
		if conn.Neighbour >= 0 {
			fc := mesh.FaceCentroids[i]
			faceField[i] = 3*fc.X + 7*fc.Y // exact face value
		} else {
			fc := mesh.FaceCentroids[i]
			faceField[i] = 3*fc.X + 7*fc.Y
		}
	}

	GreenGaussGradient(mesh, faceField, gradX, gradY)

	maxErrX, maxErrY := 0.0, 0.0
	for i := range field {
		maxErrX = max(maxErrX, math.Abs(gradX[i]-3))
		maxErrY = max(maxErrY, math.Abs(gradY[i]-7))
	}

	t.Logf("Max gradient error: gradX=%.2e, gradY=%.2e", maxErrX, maxErrY)

	if maxErrX > 1e-10 || maxErrY > 1e-10 {
		t.Errorf("Green-Gauss not exact for linear field on triangular mesh")
	}
}

//
// Rhie chow
//

func TestRhieChowFaceNormal(t *testing.T) {
	tests := []struct {
		name      string
		makeMesh  func() *geometry.Mesh
		setup     func(mesh *geometry.Mesh) (Ux, Uy, p, gradPx, gradPy, aPx, aPy []float64)
		checkFace func(i int, conn geometry.Connection, n geometry.Vec2, got float64) (float64, bool) // returns (want, ok)
	}{
		{
			name:     "uniform flow linear pressure",
			makeMesh: func() *geometry.Mesh { return geometry.MakeSimple1DMesh(10) },
			setup: func(mesh *geometry.Mesh) (Ux, Uy, p, gradPx, gradPy, aPx, aPy []float64) {
				n := len(mesh.Centroids)
				Ux, Uy, p = make([]float64, n), make([]float64, n), make([]float64, n)
				gradPx, gradPy = make([]float64, n), make([]float64, n)
				aPx, aPy = make([]float64, n), make([]float64, n)
				for i, c := range mesh.Centroids {
					Ux[i], Uy[i] = 2.0, 0.0
					p[i] = 100 * c.X
					gradPx[i], gradPy[i] = 100, 0
					aPx[i], aPy[i] = 1.0, 1.0
				}
				return
			},
			checkFace: func(i int, conn geometry.Connection, n geometry.Vec2, got float64) (float64, bool) {
				if conn.Neighbour < 0 {
					return 0, true // skip boundaries
				}
				return 2.0, floatsEqual(got, 2.0, FLOAT_TOL)
			},
		},
		{
			name:     "2D diagonal flow",
			makeMesh: func() *geometry.Mesh { return geometry.MakeRectangular2DStrip(5) },
			setup: func(mesh *geometry.Mesh) (Ux, Uy, p, gradPx, gradPy, aPx, aPy []float64) {
				n := len(mesh.Centroids)
				Ux, Uy, p = make([]float64, n), make([]float64, n), make([]float64, n)
				gradPx, gradPy = make([]float64, n), make([]float64, n)
				aPx, aPy = make([]float64, n), make([]float64, n)
				for i, c := range mesh.Centroids {
					Ux[i], Uy[i] = 3.0, 4.0
					p[i] = 2*c.X + 5*c.Y
					gradPx[i], gradPy[i] = 2.0, 5.0
					aPx[i], aPy[i] = 2.0, 2.0
				}
				return
			},
			checkFace: func(i int, conn geometry.Connection, n geometry.Vec2, got float64) (float64, bool) {
				if conn.Neighbour < 0 {
					return 0, true
				}
				want := 3.0*n.X + 4.0*n.Y
				return want, floatsEqual(got, want, FLOAT_TOL)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mesh := tt.makeMesh()
			Ux, Uy, p, gradPx, gradPy, aPx, aPy := tt.setup(mesh)
			UnormalMWI := make([]float64, len(mesh.Connections))

			RhieChowFaceNormal(mesh, Ux, Uy, p, gradPx, gradPy, aPx, aPy, UnormalMWI)

			for i, conn := range mesh.Connections {
				want, ok := tt.checkFace(i, conn, mesh.FaceNormals[i], UnormalMWI[i])
				if !ok {
					t.Errorf("face %d: got %v, want %v", i, UnormalMWI[i], want)
				}
			}
		})
	}
}

//
// Divergence
//

func TestDivergencePipeline(t *testing.T) {
	db := geometry.DomainBuilder{}
	db.AddPolygon(geometry.MakeRectangle(0, 0, 4, 1, "fluid", "south", "east", "north", "west"))
	domain, _ := db.Build()
	mesh, _ := geometry.MeshWithCells(domain, 400, 30)

	nCells := len(mesh.Centroids)
	nConns := len(mesh.Connections)

	// Case 1: Uniform flow — divergence must be machine zero
	t.Run("uniform", func(t *testing.T) {
		Ux := make([]float64, nCells)
		Uy := make([]float64, nCells)
		for i := range Ux {
			Ux[i] = 3.0
			Uy[i] = 7.0
		}
		UxF := make([]float64, nConns)
		UyF := make([]float64, nConns)
		Un := make([]float64, nConns)
		FaceInterpCDS(mesh, Ux, UxF)
		FaceInterpCDS(mesh, Uy, UyF)
		// Dirichlet everywhere with the same constant
		for _, name := range []string{"west", "east", "north", "south"} {
			DirichletFaceValuesConst(mesh, UxF, name, 3.0)
			DirichletFaceValuesConst(mesh, UyF, name, 7.0)
		}
		FaceNormalComponent(mesh, UxF, UyF, Un)
		div := make([]float64, nCells)
		Divergence(mesh, Un, div)
		l1 := NormL1(div)
		t.Logf("Uniform flow divergence L1: %.4e", l1)
		if l1 > 1e-10 {
			t.Errorf("Uniform flow should be divergence-free, got %.4e", l1)
		}
	})

	// Case 2: Linear Ux = x, Uy = -y (div-free: dUx/dx + dUy/dy = 1 - 1 = 0)
	// CDS is exact for linear fields, so this should also be ~0
	t.Run("linear_divfree", func(t *testing.T) {
		Ux := make([]float64, nCells)
		Uy := make([]float64, nCells)
		for i, c := range mesh.Centroids {
			Ux[i] = c.X
			Uy[i] = -c.Y
		}
		UxF := make([]float64, nConns)
		UyF := make([]float64, nConns)
		Un := make([]float64, nConns)
		FaceInterpCDS(mesh, Ux, UxF)
		FaceInterpCDS(mesh, Uy, UyF)
		// Set exact boundary values
		for i, conn := range mesh.Connections {
			if conn.Neighbour < 0 {
				fc := mesh.FaceCentroids[i]
				UxF[i] = fc.X
				UyF[i] = -fc.Y
			}
		}
		FaceNormalComponent(mesh, UxF, UyF, Un)
		div := make([]float64, nCells)
		Divergence(mesh, Un, div)
		l1 := NormL1(div)
		t.Logf("Linear div-free divergence L1: %.4e", l1)
		if l1 > 0.5*float64(nCells)*0.01 {
			t.Errorf("Linear div-free field should have zero divergence, got %.4e", l1)
		}
	})

	// Case 3: Linear Ux = x, Uy = 0 (div = 1 everywhere)
	// Each cell's discrete divergence should equal its volume
	t.Run("linear_unit_div", func(t *testing.T) {
		Ux := make([]float64, nCells)
		Uy := make([]float64, nCells)
		for i, c := range mesh.Centroids {
			Ux[i] = c.X
			Uy[i] = 0
		}
		UxF := make([]float64, nConns)
		UyF := make([]float64, nConns)
		Un := make([]float64, nConns)
		FaceInterpCDS(mesh, Ux, UxF)
		FaceInterpCDS(mesh, Uy, UyF)
		for i, conn := range mesh.Connections {
			if conn.Neighbour < 0 {
				fc := mesh.FaceCentroids[i]
				UxF[i] = fc.X
				UyF[i] = 0
			}
		}
		FaceNormalComponent(mesh, UxF, UyF, Un)
		div := make([]float64, nCells)
		Divergence(mesh, Un, div)

		maxErr := 0.0
		for i := range div {
			err := math.Abs(div[i] - mesh.CellVolumes[i])
			maxErr = max(maxErr, err)
		}
		t.Logf("Unit divergence max error: %.4e", maxErr)
		if maxErr > 0.01 {
			t.Errorf("div(x,0) should equal cell volume, max error = %.4e", maxErr)
		}
	})
}
