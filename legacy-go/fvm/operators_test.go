package fvm

import (
	"math"
	"testing"

	"jedn.dev/jnlcfd/geometry"
)

// ────────────────────────────────────────────────────────────────────────────
// Test helpers
// ────────────────────────────────────────────────────────────────────────────

const opTol = 1e-12

func assertSlice(t *testing.T, name string, got, want []float64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("%s: len %d, want %d", name, len(got), len(want))
	}
	for i := range got {
		if math.Abs(got[i]-want[i]) > opTol {
			t.Errorf("%s[%d] = %.10g, want %.10g (diff %.2e)",
				name, i, got[i], want[i], got[i]-want[i])
		}
	}
}

// opTestMesh creates a minimal 2-cell mesh for operator testing.
//
//   Cell 0: region "fluid" (id=1), Cell 1: region "solid" (id=2)
//
//   Connections:
//     0: owner=0, neighbour=-1  (boundary "wall")
//     1: owner=0, neighbour= 1  (internal, w=0.5)
//     2: owner=1, neighbour=-2  (boundary "inlet")
//
//   All geometry uniform: area=1, dist=1, orthFactor=1, cellVol=1, nonOrthDelta=0
//
func opTestMesh() *geometry.Mesh {
	return &geometry.Mesh{
		Centroids:   []geometry.Vec2{{X: 0.33, Y: 0.33}, {X: 0.67, Y: 0.67}},
		CellVolumes: []float64{1.0, 1.0},
		Connections: []geometry.Connection{
			{Owner: 0, Neighbour: -1},
			{Owner: 0, Neighbour: 1},
			{Owner: 1, Neighbour: -2},
		},
		FaceAreas:       []float64{1, 1, 1},
		FaceNormals:     []geometry.Vec2{{X: 0, Y: -1}, {X: 1, Y: 0}, {X: 0, Y: 1}},
		FaceCentroids:   []geometry.Vec2{{X: 0.5, Y: 0}, {X: 0.5, Y: 0.5}, {X: 0.5, Y: 1}},
		ConnectionDists: []float64{1, 1, 1},
		ConnectionVecs:  []geometry.Vec2{{X: 0, Y: -1}, {X: 0.34, Y: 0.34}, {X: 0, Y: 1}},
		InterpWeights:   []float64{1, 0.5, 1},
		OrthFactors:     []float64{1, 1, 1},
		NonOrthDeltas:   []geometry.Vec2{{X: 0, Y: 0}, {X: 0, Y: 0}, {X: 0, Y: 0}},
		CellRegions:     []int{1, 2},
		RegionNames:     map[int]string{1: "fluid", 2: "solid"},
		BoundaryNames:   map[int]string{1: "wall", 2: "inlet"},
	}
}

type opTestCase struct {
	name      string
	apply     func(*FVSystem, *geometry.Mesh)
	wantDiag  []float64
	wantLower []float64
	wantUpper []float64
	wantRhs   []float64
}

func runOpTests(t *testing.T, tests []opTestCase) {
	t.Helper()
	mesh := opTestMesh()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sys := NewFVSystem(mesh)
			tt.apply(sys, mesh)
			if tt.wantDiag != nil {
				assertSlice(t, "diag", sys.Matrix.diag, tt.wantDiag)
			}
			if tt.wantLower != nil {
				assertSlice(t, "lower", sys.Matrix.lower, tt.wantLower)
			}
			if tt.wantUpper != nil {
				assertSlice(t, "upper", sys.Matrix.upper, tt.wantUpper)
			}
			if tt.wantRhs != nil {
				assertSlice(t, "rhs", sys.Rhs, tt.wantRhs)
			}
		})
	}
}

// ────────────────────────────────────────────────────────────────────────────
// harmonicMean
// ────────────────────────────────────────────────────────────────────────────

func TestHarmonicMean(t *testing.T) {
	tests := []struct {
		gO, gN, w, want float64
	}{
		{1, 1, 0.5, 1.0},   // equal → same as arithmetic
		{3, 6, 0.5, 4.0},   // 1/(1/6 + 1/12) = 4
		{2, 8, 0.5, 3.2},   // 1/(0.25 + 0.0625) = 3.2
		{5, 5, 0.3, 5.0},   // equal → always 5 regardless of w
		{1e-30, 1, 0.5, 0}, // near-zero → clamped to 0
	}
	for _, tt := range tests {
		got := harmonicMean(tt.gO, tt.gN, tt.w)
		if math.Abs(got-tt.want) > opTol {
			t.Errorf("harmonicMean(%.4g, %.4g, %.4g) = %.10g, want %.10g",
				tt.gO, tt.gN, tt.w, got, tt.want)
		}
	}
}

// ────────────────────────────────────────────────────────────────────────────
// Laplacian — arithmetic mean
// ────────────────────────────────────────────────────────────────────────────

func TestLaplacian(t *testing.T) {
	gamma := []float64{3, 1}

	runOpTests(t, []opTestCase{
		{
			name:      "Const gamma=2",
			apply:     func(s *FVSystem, m *geometry.Mesh) { LaplacianConst(s, m, 2, nil, nil) },
			wantDiag:  []float64{2, 2},
			wantLower: []float64{-2, -2, -2},
			wantUpper: []float64{-2, -2, -2},
			wantRhs:   []float64{0, 0},
		},
		{
			// conn0(boundary): gFace=3
			// conn1(internal, w=0.5): gFace = 0.5*3 + 0.5*1 = 2
			// conn2(boundary): gFace=1
			name:      "Field gamma=[3,1]",
			apply:     func(s *FVSystem, m *geometry.Mesh) { LaplacianField(s, m, gamma, nil, nil) },
			wantDiag:  []float64{2, 2},
			wantLower: []float64{-3, -2, -1},
			wantUpper: []float64{-3, -2, -1},
			wantRhs:   []float64{0, 0},
		},
		{
			name: "Expr const delegates to Const",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				LaplacianExpr(s, m, ConstExpr(2), nil, nil)
			},
			wantDiag:  []float64{2, 2},
			wantLower: []float64{-2, -2, -2},
			wantUpper: []float64{-2, -2, -2},
		},
		{
			name: "Expr field matches Field",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				LaplacianExpr(s, m, FieldExpr(gamma), nil, nil)
			},
			wantDiag:  []float64{2, 2},
			wantLower: []float64{-3, -2, -1},
			wantUpper: []float64{-3, -2, -1},
		},
		{
			name: "Symmetry: lower equals upper",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				LaplacianField(s, m, gamma, nil, nil)
			},
			wantLower: []float64{-3, -2, -1},
			wantUpper: []float64{-3, -2, -1},
		},
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Laplacian — harmonic mean
// ────────────────────────────────────────────────────────────────────────────

func TestLaplacianHarmonic(t *testing.T) {
	// gamma=[3,6]: harmonic(3,6,0.5) = 4.0, arithmetic = 4.5
	gamma := []float64{3, 6}

	runOpTests(t, []opTestCase{
		{
			// conn0(boundary): gFace=3 (owner only)
			// conn1(internal): harmonicMean(3,6,0.5) = 4
			// conn2(boundary): gFace=6 (owner only)
			name:      "FieldHarmonic gamma=[3,6]",
			apply:     func(s *FVSystem, m *geometry.Mesh) { LaplacianFieldHarmonic(s, m, gamma, nil, nil) },
			wantDiag:  []float64{4, 4},
			wantLower: []float64{-3, -4, -6},
			wantUpper: []float64{-3, -4, -6},
		},
		{
			name: "ExprHarmonic matches FieldHarmonic",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				LaplacianExprHarmonic(s, m, FieldExpr(gamma), nil, nil)
			},
			wantDiag:  []float64{4, 4},
			wantLower: []float64{-3, -4, -6},
			wantUpper: []float64{-3, -4, -6},
		},
		{
			name: "ExprHarmonic const delegates to LaplacianConst",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				LaplacianExprHarmonic(s, m, ConstExpr(2), nil, nil)
			},
			wantDiag:  []float64{2, 2},
			wantLower: []float64{-2, -2, -2},
			wantUpper: []float64{-2, -2, -2},
		},
	})

	t.Run("harmonic less than arithmetic", func(t *testing.T) {
		mesh := opTestMesh()
		sysH := NewFVSystem(mesh)
		sysA := NewFVSystem(mesh)
		LaplacianFieldHarmonic(sysH, mesh, gamma, nil, nil)
		LaplacianField(sysA, mesh, gamma, nil, nil)

		// Internal face (conn 1): harmonic=4, arithmetic=4.5
		if sysH.Matrix.diag[0] >= sysA.Matrix.diag[0] {
			t.Errorf("harmonic diag %.6f should be < arithmetic %.6f",
				sysH.Matrix.diag[0], sysA.Matrix.diag[0])
		}
	})

	t.Run("uniform gamma matches arithmetic", func(t *testing.T) {
		mesh := opTestMesh()
		uniform := []float64{5, 5}
		sysH := NewFVSystem(mesh)
		sysA := NewFVSystem(mesh)
		LaplacianFieldHarmonic(sysH, mesh, uniform, nil, nil)
		LaplacianField(sysA, mesh, uniform, nil, nil)

		assertSlice(t, "diag", sysH.Matrix.diag, sysA.Matrix.diag)
		assertSlice(t, "lower", sysH.Matrix.lower, sysA.Matrix.lower)
		assertSlice(t, "upper", sysH.Matrix.upper, sysA.Matrix.upper)
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Laplacian — non-orthogonal correction
// ────────────────────────────────────────────────────────────────────────────

func TestLaplacianNonOrthCorrection(t *testing.T) {
	mesh := opTestMesh()
	mesh.NonOrthDeltas = []geometry.Vec2{{X: 0, Y: 0}, {X: 0.1, Y: 0.2}, {X: 0, Y: 0}}

	gradX := []float64{1.0, 2.0}
	gradY := []float64{3.0, 4.0}

	// Internal face (conn 1, w=0.5):
	//   gradXFace = 0.5*1 + 0.5*2 = 1.5
	//   gradYFace = 0.5*3 + 0.5*4 = 3.5
	//   correction = gamma * 1.0 * (0.1*1.5 + 0.2*3.5) = gamma * 0.85

	t.Run("Const", func(t *testing.T) {
		sys := NewFVSystem(mesh)
		LaplacianConst(sys, mesh, 2, gradX, gradY)
		assertSlice(t, "rhs", sys.Rhs, []float64{1.7, -1.7})
		assertSlice(t, "diag", sys.Matrix.diag, []float64{2, 2})
	})

	t.Run("Field", func(t *testing.T) {
		sys := NewFVSystem(mesh)
		LaplacianField(sys, mesh, []float64{2, 2}, gradX, gradY)
		assertSlice(t, "rhs", sys.Rhs, []float64{1.7, -1.7})
	})

	t.Run("FieldHarmonic", func(t *testing.T) {
		sys := NewFVSystem(mesh)
		LaplacianFieldHarmonic(sys, mesh, []float64{2, 2}, gradX, gradY)
		assertSlice(t, "rhs", sys.Rhs, []float64{1.7, -1.7})
	})

	t.Run("Expr", func(t *testing.T) {
		sys := NewFVSystem(mesh)
		LaplacianExpr(sys, mesh, ConstExpr(2), gradX, gradY)
		assertSlice(t, "rhs", sys.Rhs, []float64{1.7, -1.7})
	})

	t.Run("ExprHarmonic", func(t *testing.T) {
		sys := NewFVSystem(mesh)
		LaplacianExprHarmonic(sys, mesh, FieldExpr([]float64{2, 2}), gradX, gradY)
		assertSlice(t, "rhs", sys.Rhs, []float64{1.7, -1.7})
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Divergence — CDS
// ────────────────────────────────────────────────────────────────────────────

func TestDivCDS(t *testing.T) {
	Un := []float64{1, 1, 1}
	rhoField := []float64{2, 1}

	runOpTests(t, []opTestCase{
		{
			// All faces: F = 1.5*1*1 = 1.5
			// conn0(boundary): upper += F=1.5
			// conn1(internal, w=0.5): lower -= 1.5*0.5=0.75, upper += 1.5*0.5=0.75
			//   diag[0] += 0.75, diag[1] -= 0.75
			// conn2(boundary): upper += F=1.5
			name: "Const rho=1.5",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivConstCDS(s, m, 1.5, Un)
			},
			wantDiag:  []float64{0.75, -0.75},
			wantLower: []float64{0, -0.75, 0},
			wantUpper: []float64{1.5, 0.75, 1.5},
		},
		{
			// conn0: rhoFace=2 (boundary, owner), F=2
			// conn1: rhoFace = 0.5*2+0.5*1 = 1.5, F=1.5
			// conn2: rhoFace=1 (boundary, owner), F=1
			name: "Field rho=[2,1]",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivFieldCDS(s, m, rhoField, Un)
			},
			wantDiag:  []float64{0.75, -0.75},
			wantLower: []float64{0, -0.75, 0},
			wantUpper: []float64{2, 0.75, 1},
		},
		{
			name: "Expr const delegates",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivExprCDS(s, m, ConstExpr(1.5), Un)
			},
			wantDiag:  []float64{0.75, -0.75},
			wantLower: []float64{0, -0.75, 0},
			wantUpper: []float64{1.5, 0.75, 1.5},
		},
		{
			name: "Expr field matches Field",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivExprCDS(s, m, FieldExpr(rhoField), Un)
			},
			wantDiag:  []float64{0.75, -0.75},
			wantLower: []float64{0, -0.75, 0},
			wantUpper: []float64{2, 0.75, 1},
		},
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Divergence — UDS
// ────────────────────────────────────────────────────────────────────────────

func TestDivUDS(t *testing.T) {
	UnPos := []float64{1, 1, 1}
	UnNeg := []float64{-1, -1, -1}
	rhoField := []float64{2, 1}

	runOpTests(t, []opTestCase{
		{
			// F=1.5>0 everywhere
			// conn0(boundary): upper += F=1.5
			// conn1(internal): lower -= max(1.5,0)=1.5, upper -= max(-1.5,0)=0
			//   diag[0] += 1.5, diag[1] += 0
			// conn2(boundary): upper += F=1.5
			name: "Const positive flow",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivConstUDS(s, m, 1.5, UnPos)
			},
			wantDiag:  []float64{1.5, 0},
			wantLower: []float64{0, -1.5, 0},
			wantUpper: []float64{1.5, 0, 1.5},
		},
		{
			// F=-1.5<0 everywhere
			// conn1(internal): lower -= max(-1.5,0)=0, upper -= max(1.5,0)=1.5
			//   diag[0] += 0, diag[1] += 1.5
			name: "Const negative flow",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivConstUDS(s, m, 1.5, UnNeg)
			},
			wantDiag:  []float64{0, 1.5},
			wantLower: []float64{0, 0, 0},
			wantUpper: []float64{-1.5, -1.5, -1.5},
		},
		{
			// conn1: rhoFace=1.5, F=1.5>0
			name: "Field rho=[2,1] positive",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivFieldUDS(s, m, rhoField, UnPos)
			},
			wantDiag:  []float64{1.5, 0},
			wantLower: []float64{0, -1.5, 0},
			wantUpper: []float64{2, 0, 1},
		},
		{
			name: "Expr const delegates",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivExprUDS(s, m, ConstExpr(1.5), UnPos)
			},
			wantDiag:  []float64{1.5, 0},
			wantLower: []float64{0, -1.5, 0},
			wantUpper: []float64{1.5, 0, 1.5},
		},
		{
			name: "Expr field matches Field",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				DivExprUDS(s, m, FieldExpr(rhoField), UnPos)
			},
			wantDiag:  []float64{1.5, 0},
			wantLower: []float64{0, -1.5, 0},
			wantUpper: []float64{2, 0, 1},
		},
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Source Su — with region filtering
// ────────────────────────────────────────────────────────────────────────────

func TestSuSource(t *testing.T) {
	field := []float64{10, 20}

	runOpTests(t, []opTestCase{
		{
			name:    "Const all regions",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuConst(s, m, 5) },
			wantRhs: []float64{5, 5},
		},
		{
			name:    "Const fluid only",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuConst(s, m, 5, "fluid") },
			wantRhs: []float64{5, 0},
		},
		{
			name:    "Const solid only",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuConst(s, m, 5, "solid") },
			wantRhs: []float64{0, 5},
		},
		{
			name:    "Field all regions",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuField(s, m, field) },
			wantRhs: []float64{10, 20},
		},
		{
			name:    "Field fluid only",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuField(s, m, field, "fluid") },
			wantRhs: []float64{10, 0},
		},
		{
			name:    "Expr const all regions delegates",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuExpr(s, m, ConstExpr(5)) },
			wantRhs: []float64{5, 5},
		},
		{
			name:    "Expr const with region does not delegate",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuExpr(s, m, ConstExpr(5), "solid") },
			wantRhs: []float64{0, 5},
		},
		{
			name:    "Expr field fluid only",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuExpr(s, m, FieldExpr(field), "fluid") },
			wantRhs: []float64{10, 0},
		},
		{
			name:    "Integrated (no volume multiply)",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuIntegrated(s, field) },
			wantRhs: []float64{10, 20},
		},
		{
			name:    "FieldScaled coeff=3",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuFieldScaled(s, 3, field) },
			wantRhs: []float64{30, 60},
		},
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Source Sp — with region filtering
// ────────────────────────────────────────────────────────────────────────────

func TestSpSource(t *testing.T) {
	field := []float64{10, 20}

	runOpTests(t, []opTestCase{
		{
			name:     "Const all regions",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpConst(s, m, -3) },
			wantDiag: []float64{-3, -3},
		},
		{
			name:     "Const fluid only",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpConst(s, m, -3, "fluid") },
			wantDiag: []float64{-3, 0},
		},
		{
			name:     "Field all regions",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpField(s, m, field) },
			wantDiag: []float64{10, 20},
		},
		{
			name:     "Field solid only",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpField(s, m, field, "solid") },
			wantDiag: []float64{0, 20},
		},
		{
			name:     "Expr const delegates",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpExpr(s, m, ConstExpr(-3)) },
			wantDiag: []float64{-3, -3},
		},
		{
			name:     "Expr const with region does not delegate",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpExpr(s, m, ConstExpr(-3), "fluid") },
			wantDiag: []float64{-3, 0},
		},
		{
			name:     "Integrated (no volume multiply)",
			apply:    func(s *FVSystem, m *geometry.Mesh) { SpIntegrated(s, field) },
			wantDiag: []float64{10, 20},
		},
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Explicit divergence source
// ────────────────────────────────────────────────────────────────────────────

func TestSuDivergence(t *testing.T) {
	Un := []float64{1, 1, 1}
	rhoField := []float64{2, 1}

	runOpTests(t, []opTestCase{
		{
			// conn0: flux=2*1*1=2, rhs[0]+=2
			// conn1: flux=2*1*1=2, rhs[0]+=2, rhs[1]-=2
			// conn2: flux=2*1*1=2, rhs[1]+=2
			name:    "Const rho=2",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuDivergenceConst(s, m, 2, Un) },
			wantRhs: []float64{4, 0},
		},
		{
			// conn0: rhoFace=2 (boundary), flux=2, rhs[0]+=2
			// conn1: rhoFace=0.5*2+0.5*1=1.5, flux=1.5, rhs[0]+=1.5, rhs[1]-=1.5
			// conn2: rhoFace=1 (boundary), flux=1, rhs[1]+=1
			name:    "Field rho=[2,1]",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuDivergenceField(s, m, rhoField, Un) },
			wantRhs: []float64{3.5, -0.5},
		},
		{
			name:    "Expr const delegates",
			apply:   func(s *FVSystem, m *geometry.Mesh) { SuDivergenceExpr(s, m, ConstExpr(2), Un) },
			wantRhs: []float64{4, 0},
		},
		{
			name: "Expr field matches Field",
			apply: func(s *FVSystem, m *geometry.Mesh) {
				SuDivergenceExpr(s, m, FieldExpr(rhoField), Un)
			},
			wantRhs: []float64{3.5, -0.5},
		},
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Operator composition: Laplacian + source = physical equation
// ────────────────────────────────────────────────────────────────────────────

func TestOperatorComposition(t *testing.T) {
	mesh := opTestMesh()
	sys := NewFVSystem(mesh)

	// Laplacian(gamma=2) + Su(5 on fluid) + Sp(-1 on solid)
	LaplacianConst(sys, mesh, 2, nil, nil)
	SuConst(sys, mesh, 5, "fluid")
	SpConst(sys, mesh, -1, "solid")

	assertSlice(t, "diag", sys.Matrix.diag, []float64{2, 1})
	assertSlice(t, "rhs", sys.Rhs, []float64{5, 0})
	assertSlice(t, "lower", sys.Matrix.lower, []float64{-2, -2, -2})
	assertSlice(t, "upper", sys.Matrix.upper, []float64{-2, -2, -2})
}

// ────────────────────────────────────────────────────────────────────────────
// BoussinesqExpr
// ────────────────────────────────────────────────────────────────────────────

func TestBoussinesqExpr(t *testing.T) {
	T := []float64{310, 290}
	rho := 1.2
	beta := 3e-3
	Tref := 300.0
	gy := -9.81

	expr := BoussinesqExpr(rho, beta, Tref, gy, FieldExpr(T))

	// coeff inside = -rho * beta * gy = -1.2 * 3e-3 * (-9.81) = 0.035316
	// cell 0: 0.035316 * (310-300) =  0.35316
	// cell 1: 0.035316 * (290-300) = -0.35316
	coeff := -rho * beta * gy
	want0 := coeff * (T[0] - Tref)
	want1 := coeff * (T[1] - Tref)

	if math.Abs(expr.Eval(0)-want0) > opTol {
		t.Errorf("cell 0: got %.10g, want %.10g", expr.Eval(0), want0)
	}
	if math.Abs(expr.Eval(1)-want1) > opTol {
		t.Errorf("cell 1: got %.10g, want %.10g", expr.Eval(1), want1)
	}
	if expr.IsConst {
		t.Error("BoussinesqExpr should not be const")
	}

	t.Run("hot cell buoys upward", func(t *testing.T) {
		if expr.Eval(0) <= 0 {
			t.Errorf("hot cell should have positive buoyancy, got %g", expr.Eval(0))
		}
	})

	t.Run("cold cell sinks", func(t *testing.T) {
		if expr.Eval(1) >= 0 {
			t.Errorf("cold cell should have negative buoyancy, got %g", expr.Eval(1))
		}
	})

	t.Run("zero gravity", func(t *testing.T) {
		zeroExpr := BoussinesqExpr(rho, beta, Tref, 0, FieldExpr(T))
		if zeroExpr.Eval(0) != 0 {
			t.Errorf("zero gravity should give zero source, got %g", zeroExpr.Eval(0))
		}
	})

	t.Run("at Tref no source", func(t *testing.T) {
		Tuniform := []float64{300, 300}
		refExpr := BoussinesqExpr(rho, beta, Tref, gy, FieldExpr(Tuniform))
		if refExpr.Eval(0) != 0 {
			t.Errorf("T=Tref should give zero source, got %g", refExpr.Eval(0))
		}
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Region helpers
// ────────────────────────────────────────────────────────────────────────────

func TestRegionMask(t *testing.T) {
	mesh := opTestMesh()

	t.Run("nil mask contains everything", func(t *testing.T) {
		mask := AllRegions()
		if !mask.Contains(1) || !mask.Contains(2) || !mask.Contains(999) {
			t.Error("nil mask should contain all regions")
		}
	})

	t.Run("empty names returns nil", func(t *testing.T) {
		mask := RegionsFromNames(mesh)
		if mask != nil {
			t.Error("no names should return nil mask")
		}
	})

	t.Run("fluid mask", func(t *testing.T) {
		mask := RegionsFromNames(mesh, "fluid")
		if !mask.Contains(1) {
			t.Error("should contain fluid (id=1)")
		}
		if mask.Contains(2) {
			t.Error("should not contain solid (id=2)")
		}
	})
}

func TestCellsInRegions(t *testing.T) {
	mesh := opTestMesh()

	tests := []struct {
		name    string
		regions []string
		want    []int
	}{
		{"fluid", []string{"fluid"}, []int{0}},
		{"solid", []string{"solid"}, []int{1}},
		{"both", []string{"fluid", "solid"}, []int{0, 1}},
		{"nonexistent", []string{"nonexistent"}, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CellsInRegions(mesh, tt.regions...)
			if len(got) != len(tt.want) {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Errorf("[%d] = %d, want %d", i, got[i], tt.want[i])
				}
			}
		})
	}

	t.Run("no args returns all cells", func(t *testing.T) {
		got := CellsInRegions(mesh)
		if len(got) != 2 {
			t.Fatalf("got %v, want all cells", got)
		}
	})
}

func TestCellsNotInRegions(t *testing.T) {
	mesh := opTestMesh()

	tests := []struct {
		name    string
		regions []string
		want    []int
	}{
		{"exclude fluid", []string{"fluid"}, []int{1}},
		{"exclude solid", []string{"solid"}, []int{0}},
		{"exclude both", []string{"fluid", "solid"}, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CellsNotInRegions(mesh, tt.regions...)
			if len(got) != len(tt.want) {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Errorf("[%d] = %d, want %d", i, got[i], tt.want[i])
				}
			}
		})
	}

	t.Run("no args returns nil", func(t *testing.T) {
		got := CellsNotInRegions(mesh)
		if got != nil {
			t.Fatalf("got %v, want nil", got)
		}
	})
}

func TestRegionExpr(t *testing.T) {
	mesh := opTestMesh()

	t.Run("dispatches by region", func(t *testing.T) {
		expr := RegionExpr(mesh, map[string]Expression{
			"fluid": ConstExpr(0.026),
			"solid": ConstExpr(50),
		}, ConstExpr(1.0))

		if math.Abs(expr.Eval(0)-0.026) > opTol {
			t.Errorf("cell 0 (fluid): got %g, want 0.026", expr.Eval(0))
		}
		if math.Abs(expr.Eval(1)-50) > opTol {
			t.Errorf("cell 1 (solid): got %g, want 50", expr.Eval(1))
		}
		if expr.IsConst {
			t.Error("RegionExpr should not be const")
		}
	})

	t.Run("fallback for unmapped region", func(t *testing.T) {
		expr := RegionExpr(mesh, map[string]Expression{
			"fluid": ConstExpr(0.026),
		}, ConstExpr(999))

		if math.Abs(expr.Eval(0)-0.026) > opTol {
			t.Errorf("cell 0 (mapped): got %g, want 0.026", expr.Eval(0))
		}
		if math.Abs(expr.Eval(1)-999) > opTol {
			t.Errorf("cell 1 (fallback): got %g, want 999", expr.Eval(1))
		}
	})

	t.Run("field expression per region", func(t *testing.T) {
		k := []float64{100, 200}
		expr := RegionExpr(mesh, map[string]Expression{
			"fluid": ConstExpr(0.026),
			"solid": FieldExpr(k),
		}, ConstExpr(0))

		if math.Abs(expr.Eval(1)-200) > opTol {
			t.Errorf("cell 1 (solid field): got %g, want 200", expr.Eval(1))
		}
	})
}
