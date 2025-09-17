package geometry

import (
	"math"
	"slices"
	"testing"
)

func TestDedupVertices(t *testing.T) {
	verticesX := []float32{0.0, 1.0, 0.0000001, 2.0}
	verticesY := []float32{0.0, 0.0, 0.0000001, 0.0}
	tolerance := float32(0.001)

	dedupX, dedupY, indexMap := dedupVertices(verticesX, verticesY, tolerance)

	expectedX := []float32{0.0, 1.0, 2.0}
	expectedY := []float32{0.0, 0.0, 0.0}
	expectedIndexMap := []int{0, 1, 0, 2}

	for _, tt := range []struct {
		got  []float32
		want []float32
		name string
	}{
		{dedupX, expectedX, "dedupX"},
		{dedupY, expectedY, "dedupY"},
	} {
		if !floatSlicesEqual(tt.got, tt.want, 1e-6) {
			t.Errorf("dedupVertices, %s error: got %v, want %v",
				tt.name, tt.got, tt.want)
		}
	}

	if !intSlicesEqual(indexMap, expectedIndexMap) {
		t.Errorf("dedupVertices indexMap error, got: %v, want: %v", indexMap, []int{0, 1, 2})
	}
}

func TestDedupVerticesNoDuplicates(t *testing.T) {
	verticesX := []float32{0.0, 1.0, 2.0}
	verticesY := []float32{0.0, 1.0, 2.0}
	tolerance := float32(0.001)

	dedupX, dedupY, indexMap := dedupVertices(verticesX, verticesY, tolerance)

	for _, tt := range []struct {
		got  []float32
		want []float32
		name string
	}{
		{dedupX, verticesX, "dedupX"},
		{dedupY, verticesY, "dedupY"},
	} {
		if !floatSlicesEqual(tt.got, tt.want, 1e-6) {
			t.Errorf("dedupVertices (no duplicates), %s error: got %v, want %v",
				tt.name, tt.got, tt.want)
		}
	}

	if !intSlicesEqual(indexMap, []int{0, 1, 2}) {
		t.Errorf("dedupVertices indexMap error, got: %v, want: %v", indexMap, []int{0, 1, 2})
	}
}

func TestRemapVertexIndices(t *testing.T) {
	existingVertexIndices := []int{0, 1, 2, 3, 0, 1, 2, 3}
	indexMap := []int{0, 2, 2, 0} // 1 -> 2, 3 -> 0
	want := []int{0, 2, 2, 0, 0, 2, 2, 0}

	if got := remapVertexIndices(existingVertexIndices, indexMap); !intSlicesEqual(got, want) {
		t.Errorf("remapVertexIndices error, got: %v, want: %v", got, want)
	}
}

func TestCalculateCellGeometry(t *testing.T) {
	cellVolumes, centroidsX, centroidsY := calculateCellGeometry(sample2x2MeshPolygons())
	expectedCV := []float32{1, 1, 1, 1}
	expectedCX := []float32{0.5, 1.5, 0.5, 1.5}
	expectedCY := []float32{0.5, 0.5, 1.5, 1.5}

	for _, tt := range []struct {
		got  []float32
		want []float32
		name string
	}{
		{cellVolumes, expectedCV, "cellVolumes"},
		{centroidsX, expectedCX, "centroidsX"},
		{centroidsY, expectedCY, "centroidsY"},
	} {
		if !floatSlicesEqual(tt.got, tt.want, 1e-6) {
			t.Errorf("calculateCellGeometry, %s error: got: %v, want: %v", tt.name, tt.got, tt.want)
		}
	}
}

func TestCalculateFaceGeometry(t *testing.T) {
	faceAreas, faceNormalsX, faceNormalsY := calculateFaceGeometry(sample2x2MeshPolygons())
	expectedFaceAreas := []float32{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
	expectedFaceNormalsX := []float32{0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1}
	expectedFaceNormalsY := []float32{-1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0}

	for _, tt := range []struct {
		got  []float32
		want []float32
		name string
	}{
		{faceAreas, expectedFaceAreas, "faceAreas"},
		{faceNormalsX, expectedFaceNormalsX, "faceNormalsX"},
		{faceNormalsY, expectedFaceNormalsY, "faceNormalsY"},
	} {
		if !floatSlicesEqual(tt.got, tt.want, 1e-6) {
			t.Errorf("calculateFaceGeometry, %s error: got: %v, want %v",
				tt.name, tt.got, tt.want)
		}
	}
}

func TestDeriveConnectivity(t *testing.T) {
	_, _, vertexIndices, faceStarts := sample2x2MeshPolygons()
	faceMarkers := sample2x2MeshFaceMarkers()

	neighbourIndices := deriveConnectivity(vertexIndices, faceStarts, faceMarkers)
	expectedNeighbourIndices := []int{
		-1, 1, 2, -2,
		-3, -4, 3, 0,
		0, 3, -5, -6,
		1, -7, -8, 2,
	}

	if !intSlicesEqual(neighbourIndices, expectedNeighbourIndices) {
		t.Errorf("deriveConnectivity neighbourIndices error: got: %v, want: %v",
			neighbourIndices, expectedNeighbourIndices)
	}
}

func TestCalculateConnectivityGeometry(t *testing.T) {
	vX, vY, vI, fS := sample2x2MeshPolygons()
	fM := sample2x2MeshFaceMarkers()
	_, cX, cY := calculateCellGeometry(vX, vY, vI, fS)
	nI := deriveConnectivity(vI, fS, fM)

	connectionVectorsX,
		connectionVectorsY,
		connectionDistances,
		faceInterpolationWeights := calculateConnectivityGeometry(cX, cY, nI, vX, vY, vI, fS)

	expectedConnectionVectorsX := []float32{0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1}
	expectedConnectionVectorsY := []float32{-1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0}
	expectedConnectionDistances := []float32{0.5, 1, 1, 0.5, 0.5, 0.5, 1, 1, 1, 1, 0.5, 0.5, 1, 0.5, 0.5, 1}
	expectedFaceInterpolationWeights := []float32{1, 0.5, 0.5, 1, 1, 1, 0.5, 0.5, 0.5, 0.5, 1, 1, 0.5, 1, 1, 0.5}

	for _, tt := range []struct {
		got  []float32
		want []float32
		name string
	}{
		{faceInterpolationWeights, expectedFaceInterpolationWeights, "faceInterpolationWeights"},
		{connectionVectorsX, expectedConnectionVectorsX, "connectionVectorsX"},
		{connectionVectorsY, expectedConnectionVectorsY, "connectionVectorsY"},
		{connectionDistances, expectedConnectionDistances, "connectionDistances"},
	} {
		if !floatSlicesEqual(tt.got, tt.want, 1e-6) {
			t.Errorf("calculateConnectivityGeometry, %s error: got: %v, want: %v",
				tt.name, tt.got, tt.want)
		}
	}
}

// helpers
func floatSlicesEqual(got, want []float32, tolerance float32) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if math.Abs(float64(got[i]-want[i])) > float64(tolerance) {
			return false
		}
	}

	return true
}

func intSlicesEqual(got, want []int) bool {
	return slices.Equal(got, want)
}

func sample2x2MeshPolygons() (verticesX, verticesY []float32, vertexIndices, faceStarts []int) {
	verticesX = []float32{0, 1, 2, 0, 1, 2, 0, 1, 2}
	verticesY = []float32{0, 0, 0, 1, 1, 1, 2, 2, 2}

	// CCW from top-left (CCW required, starting point not)
	// NOTE: origin is bottom-left
	vertexIndices = []int{
		0, 1, 4, 3,
		1, 2, 5, 4,
		3, 4, 7, 6,
		4, 5, 8, 7,
	}

	faceStarts = []int{0, 4, 8, 12, 16} // fenceposted

	return
}

func sample2x2MeshFaceMarkers() []int {
	return []int{
		2, -1, -1, 3,
		2, 1, -1, -1,
		-1, -1, 0, 3,
		-1, 1, 0, -1,
	}
}
