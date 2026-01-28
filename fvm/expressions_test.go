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
