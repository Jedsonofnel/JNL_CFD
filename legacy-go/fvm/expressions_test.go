package fvm

import (
	"testing"
)

func TestExpressions(t *testing.T) {
	field := []float64{1, 2, 3, 4, 5}

	tests := []struct {
		name      string
		expr      Expression
		wantConst bool
		want      []float64 // expected values at indices 0-4
	}{
		// Basic expressions
		{
			name:      "Constant",
			expr:      ConstExpr(42),
			wantConst: true,
			want:      []float64{42, 42, 42, 42, 42},
		},
		{
			name:      "Field",
			expr:      FieldExpr(field),
			wantConst: false,
			want:      []float64{1, 2, 3, 4, 5},
		},

		// Arithmetic: Const + Const → Const
		{
			name:      "Add constants",
			expr:      AddExpr(ConstExpr(10), ConstExpr(5)),
			wantConst: true,
			want:      []float64{15, 15, 15, 15, 15},
		},
		{
			name:      "Mul constants",
			expr:      MulExpr(ConstExpr(3), ConstExpr(7)),
			wantConst: true,
			want:      []float64{21, 21, 21, 21, 21},
		},
		{
			name:      "Sub constants",
			expr:      SubExpr(ConstExpr(10), ConstExpr(3)),
			wantConst: true,
			want:      []float64{7, 7, 7, 7, 7},
		},
		{
			name:      "Div constants",
			expr:      DivExpr(ConstExpr(20), ConstExpr(4)),
			wantConst: true,
			want:      []float64{5, 5, 5, 5, 5},
		},

		// Arithmetic: Field + Const → Not const
		{
			name:      "Add field + const",
			expr:      AddExpr(FieldExpr(field), ConstExpr(10)),
			wantConst: false,
			want:      []float64{11, 12, 13, 14, 15},
		},
		{
			name:      "Mul field * const",
			expr:      MulExpr(FieldExpr(field), ConstExpr(2)),
			wantConst: false,
			want:      []float64{2, 4, 6, 8, 10},
		},
		{
			name:      "Div const / field",
			expr:      DivExpr(ConstExpr(10), FieldExpr(field)),
			wantConst: false,
			want:      []float64{10, 5, 10.0 / 3, 2.5, 2},
		},

		// Arithmetic: Field + Field → Not const
		{
			name:      "Add field + field",
			expr:      AddExpr(FieldExpr(field), FieldExpr(field)),
			wantConst: false,
			want:      []float64{2, 4, 6, 8, 10},
		},
		{
			name:      "Mul field * field",
			expr:      MulExpr(FieldExpr(field), FieldExpr(field)),
			wantConst: false,
			want:      []float64{1, 4, 9, 16, 25},
		},

		// Unary operations
		{
			name:      "Neg constant",
			expr:      NegExpr(ConstExpr(5)),
			wantConst: true,
			want:      []float64{-5, -5, -5, -5, -5},
		},
		{
			name:      "Neg field",
			expr:      NegExpr(FieldExpr(field)),
			wantConst: false,
			want:      []float64{-1, -2, -3, -4, -5},
		},
		{
			name:      "Pow constant",
			expr:      PowExpr(ConstExpr(2), 3),
			wantConst: true,
			want:      []float64{8, 8, 8, 8, 8},
		},
		{
			name:      "Pow field",
			expr:      PowExpr(FieldExpr(field), 2),
			wantConst: false,
			want:      []float64{1, 4, 9, 16, 25},
		},

		// Nested expressions
		{
			name:      "Nested constants (3*2 + 5)",
			expr:      AddExpr(MulExpr(ConstExpr(3), ConstExpr(2)), ConstExpr(5)),
			wantConst: true,
			want:      []float64{11, 11, 11, 11, 11},
		},
		{
			name:      "Nested mixed (field*2 + 10)",
			expr:      AddExpr(MulExpr(FieldExpr(field), ConstExpr(2)), ConstExpr(10)),
			wantConst: false,
			want:      []float64{12, 14, 16, 18, 20},
		},
		{
			name:      "Pressure-like: rho / field",
			expr:      DivExpr(ConstExpr(1.2), FieldExpr(field)),
			wantConst: false,
			want:      []float64{1.2, 0.6, 0.4, 0.3, 0.24},
		},

		// ScaleExpr
		{
			name:      "Scale const folds",
			expr:      ScaleExpr(ConstExpr(5), 3),
			wantConst: true,
			want:      []float64{15, 15, 15, 15, 15},
		},
		{
			name:      "Scale field",
			expr:      ScaleExpr(FieldExpr(field), 0.5),
			wantConst: false,
			want:      []float64{0.5, 1, 1.5, 2, 2.5},
		},
		{
			name:      "Scale by zero",
			expr:      ScaleExpr(FieldExpr(field), 0),
			wantConst: false,
			want:      []float64{0, 0, 0, 0, 0},
		},
		{
			name:      "Scale nested (field*2 scaled by 3 = field*6)",
			expr:      ScaleExpr(MulExpr(FieldExpr(field), ConstExpr(2)), 3),
			wantConst: false,
			want:      []float64{6, 12, 18, 24, 30},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Check constant folding
			if got := tt.expr.IsConst; got != tt.wantConst {
				t.Errorf("IsConst = %v, want %v", got, tt.wantConst)
			}

			// Check values at each index
			for i, want := range tt.want {
				got := tt.expr.Eval(i)
				if !floatsEqual(got, want, FLOAT_TOL) {
					t.Errorf("Eval(%d) = %v, want %v", i, got, want)
				}
			}
		})
	}
}

func TestExpressionMutations(t *testing.T) {
	field := []float64{1, 2, 3, 4, 5}
	expr := FieldExpr(field)

	tests := []struct {
		name   string
		init   []float64
		mutate func([]float64)
		want   []float64
	}{
		{
			name:   "Apply overwrites",
			init:   []float64{99, 99, 99, 99, 99},
			mutate: func(dst []float64) { expr.Apply(dst) },
			want:   []float64{1, 2, 3, 4, 5},
		},
		{
			name:   "AddInto accumulates",
			init:   []float64{10, 20, 30, 40, 50},
			mutate: func(dst []float64) { expr.AddInto(dst) },
			want:   []float64{11, 22, 33, 44, 55},
		},
		{
			name:   "SubFrom subtracts",
			init:   []float64{10, 20, 30, 40, 50},
			mutate: func(dst []float64) { expr.SubFrom(dst) },
			want:   []float64{9, 18, 27, 36, 45},
		},
		{
			name:   "MulInto multiplies",
			init:   []float64{10, 20, 30, 40, 50},
			mutate: func(dst []float64) { expr.MulInto(dst) },
			want:   []float64{10, 40, 90, 160, 250},
		},
		{
			name:   "Apply const",
			init:   []float64{99, 99, 99, 99, 99},
			mutate: func(dst []float64) { ConstExpr(7).Apply(dst) },
			want:   []float64{7, 7, 7, 7, 7},
		},
		{
			name: "AddInto nested tree",
			init: []float64{0, 0, 0, 0, 0},
			mutate: func(dst []float64) {
				// (field * 2) + 10
				AddExpr(MulExpr(FieldExpr(field), ConstExpr(2)), ConstExpr(10)).AddInto(dst)
			},
			want: []float64{12, 14, 16, 18, 20},
		},
		{
			name: "Chained mutations",
			init: []float64{100, 100, 100, 100, 100},
			mutate: func(dst []float64) {
				expr.SubFrom(dst)         // 99,98,97,96,95
				ConstExpr(5).AddInto(dst) // 104,103,102,101,100
			},
			want: []float64{104, 103, 102, 101, 100},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dst := make([]float64, len(tt.init))
			copy(dst, tt.init)
			tt.mutate(dst)
			for i, want := range tt.want {
				if !floatsEqual(dst[i], want, FLOAT_TOL) {
					t.Errorf("dst[%d] = %v, want %v", i, dst[i], want)
				}
			}
		})
	}
}

func TestResolveInto(t *testing.T) {
	field := []float64{1, 2, 3, 4, 5}

	tests := []struct {
		name string
		expr Expression
		want []float64
	}{
		{
			name: "Const",
			expr: ConstExpr(42),
			want: []float64{42, 42, 42, 42, 42},
		},
		{
			name: "Field",
			expr: FieldExpr(field),
			want: []float64{1, 2, 3, 4, 5},
		},
		{
			name: "Nested",
			expr: AddExpr(FieldExpr(field), ConstExpr(10)),
			want: []float64{11, 12, 13, 14, 15},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dst := make([]float64, 5)
			tt.expr.ResolveInto(dst)
			for i, want := range tt.want {
				if !floatsEqual(dst[i], want, FLOAT_TOL) {
					t.Errorf("dst[%d] = %v, want %v", i, dst[i], want)
				}
			}
		})
	}
}

func TestCellVolExpr(t *testing.T) {
	mesh := opTestMesh() // from operators_test.go — volumes are [1, 1]
	expr := CellVolExpr(mesh)

	if expr.IsConst {
		t.Error("CellVolExpr should not be const")
	}
	if expr.Eval(0) != 1.0 || expr.Eval(1) != 1.0 {
		t.Errorf("got [%g, %g], want [1, 1]", expr.Eval(0), expr.Eval(1))
	}
}

func TestDiagExpr(t *testing.T) {
	mesh := opTestMesh()
	sys := NewFVSystem(mesh)
	sys.Matrix.diag[0] = 7
	sys.Matrix.diag[1] = 13

	expr := DiagExpr(sys)

	if expr.IsConst {
		t.Error("DiagExpr should not be const")
	}
	if expr.Eval(0) != 7 || expr.Eval(1) != 13 {
		t.Errorf("got [%g, %g], want [7, 13]", expr.Eval(0), expr.Eval(1))
	}

	// DiagExpr should reflect mutations (it captures sys by pointer)
	sys.Matrix.diag[0] = 99
	if expr.Eval(0) != 99 {
		t.Errorf("after mutation got %g, want 99", expr.Eval(0))
	}
}
