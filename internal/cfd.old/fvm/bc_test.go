package fvm

import (
	"testing"
)

func TestScalarDirichletResolve(t *testing.T) {
	mesh := sample1x5StructuredMesh()
	dirichletEast := ScalarDirichlet{Value: 5}.Resolve(mesh, "eastBorder")

	wantedType := ScalarDirichletType
	if got := dirichletEast.bcType; got != wantedType {
		t.Errorf("type error: got: %v, want: %v", got, wantedType)
	}

	var wantedValue float32 = 5
	if got := dirichletEast.value; got != wantedValue {
		t.Errorf("value error: got :%v, want: %v", got, wantedValue)
	}

	wantedCellIndices := []int{4}
	if got := dirichletEast.cellIndices; !intSlicesEqual(got, wantedCellIndices) {
		t.Errorf("cellIndices error: got: %v, want: %v", got, wantedCellIndices)
	}

	wantedBoundaryIndices := []int{10}
	if got := dirichletEast.boundaryIndices; !intSlicesEqual(got, wantedBoundaryIndices) {
		t.Errorf("boundaryIndices error: got: %v, want: %v",
			got, wantedBoundaryIndices)
	}
}
