package geometry

import (
	"math"
	"testing"

	"jedn.dev/jnlcfd/geometry/triangle"
)

const floatTolerance = 1e-9

func assertFloatEqual(t *testing.T, expected, actual float64, msg string) {
	t.Helper()
	if math.Abs(expected-actual) > floatTolerance {
		t.Errorf("%s: expected %.10f, got %.10f (diff: %.2e)", msg, expected, actual, math.Abs(expected-actual))
	}
}

func assertVec2Equal(t *testing.T, expected, actual Vec2, msg string) {
	t.Helper()
	if math.Abs(expected.X-actual.X) > floatTolerance || math.Abs(expected.Y-actual.Y) > floatTolerance {
		t.Errorf("%s: expected (%.10f, %.10f), got (%.10f, %.10f)",
			msg, expected.X, expected.Y, actual.X, actual.Y)
	}
}

//
// Test dedupVertices
//

func TestDedupVertices_ExactDuplicates(t *testing.T) {
	vertices := []Vec2{
		{0, 0},
		{1, 0},
		{1, 0}, // exact duplicate
		{0, 1},
	}

	dedup, indexMap := dedupVertices(vertices, 1e-6)

	if len(dedup) != 3 {
		t.Errorf("expected 3 unique vertices, got %d", len(dedup))
	}

	if indexMap[1] != indexMap[2] {
		t.Errorf("duplicate vertices should map to same index: %d != %d", indexMap[1], indexMap[2])
	}
}

func TestDedupVertices_WithinTolerance(t *testing.T) {
	vertices := []Vec2{
		{0, 0},
		{1, 0},
		{1.0 + 5e-7, 5e-7}, // within tolerance of (1,0)
		{0, 1},
	}

	dedup, indexMap := dedupVertices(vertices, 1e-6)

	if len(dedup) != 3 {
		t.Errorf("expected 3 unique vertices after deduplication, got %d", len(dedup))
	}

	if indexMap[1] != indexMap[2] {
		t.Errorf("near-duplicate vertices should map to same index")
	}
}

func TestDedupVertices_OutsideTolerance(t *testing.T) {
	vertices := []Vec2{
		{0, 0},
		{1, 0},
		{1.0 + 5e-5, 0}, // outside tolerance
		{0, 1},
	}

	dedup, indexMap := dedupVertices(vertices, 1e-6)

	if len(dedup) != 4 {
		t.Errorf("expected 4 unique vertices, got %d", len(dedup))
	}

	if indexMap[1] == indexMap[2] {
		t.Errorf("vertices outside tolerance should have different indices")
	}
}

func TestDedupVertices_NegativeCoordinates(t *testing.T) {
	vertices := []Vec2{
		{-1, -1},
		{-1.0 + 5e-7, -1.0 + 5e-7}, // near duplicate
		{0, 0},
		{1, 1},
	}

	dedup, indexMap := dedupVertices(vertices, 1e-6)

	if len(dedup) != 3 {
		t.Errorf("expected 3 unique vertices with negative coords, got %d", len(dedup))
	}

	if indexMap[0] != indexMap[1] {
		t.Errorf("near-duplicate negative vertices should map to same index")
	}
}

func TestDedupVertices_PreservesIndexMapping(t *testing.T) {
	vertices := []Vec2{
		{0, 0},
		{1, 0},
		{0.5, 0.5},
	}

	dedup, indexMap := dedupVertices(vertices, 1e-6)

	// Verify all original vertices can be found in dedup via indexMap
	for i, v := range vertices {
		mappedIdx := indexMap[i]
		dedupVert := dedup[mappedIdx]
		if math.Abs(v.X-dedupVert.X) > 1e-5 || math.Abs(v.Y-dedupVert.Y) > 1e-5 {
			t.Errorf("vertex %d mapped incorrectly: original (%.6f, %.6f), mapped to (%.6f, %.6f)",
				i, v.X, v.Y, dedupVert.X, dedupVert.Y)
		}
	}
}

//
// Test calculateCellGeometry
//

func TestCalculateCellGeometry_UnitTriangle(t *testing.T) {
	// Right triangle: (0,0), (1,0), (0,1)
	vertices := []Vec2{{0, 0}, {1, 0}, {0, 1}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	volumes, centroids := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	assertFloatEqual(t, 0.5, volumes[0], "unit triangle area")
	assertVec2Equal(t, Vec2{1.0 / 3.0, 1.0 / 3.0}, centroids[0], "unit triangle centroid")
}

func TestCalculateCellGeometry_EquilateralTriangle(t *testing.T) {
	// Equilateral triangle with side length 2
	h := math.Sqrt(3.0)
	vertices := []Vec2{{0, 0}, {2, 0}, {1, h}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	volumes, centroids := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	expectedArea := math.Sqrt(3.0) // area = (sqrt(3)/4) * 4 = sqrt(3)
	assertFloatEqual(t, expectedArea, volumes[0], "equilateral triangle area")
	assertVec2Equal(t, Vec2{1.0, h / 3.0}, centroids[0], "equilateral triangle centroid")
}

func TestCalculateCellGeometry_MultipleTriangles(t *testing.T) {
	// Two triangles
	vertices := []Vec2{
		{0, 0}, {1, 0}, {0, 1}, // tri 0
		{1, 0}, {1, 1}, {0, 1}, // tri 1 (shares edge)
	}
	vertexIndices := []int{0, 1, 2, 3, 4, 5}
	faceStarts := []int{0, 3, 6}

	volumes, _ := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	if len(volumes) != 2 {
		t.Fatalf("expected 2 cells, got %d", len(volumes))
	}

	assertFloatEqual(t, 0.5, volumes[0], "triangle 0 area")
	assertFloatEqual(t, 0.5, volumes[1], "triangle 1 area")
}

func TestCalculateCellGeometry_LargeTriangle(t *testing.T) {
	// Scaled triangle to test numerical stability
	scale := 1000.0
	vertices := []Vec2{{0, 0}, {scale, 0}, {0, scale}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	volumes, _ := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	expectedArea := 0.5 * scale * scale
	assertFloatEqual(t, expectedArea, volumes[0], "large triangle area")
}

func TestCalculateCellGeometry_PanicOnNegativeVolume(t *testing.T) {
	// Clockwise winding should give negative area and panic
	vertices := []Vec2{{0, 0}, {0, 1}, {1, 0}} // CW instead of CCW
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("expected panic for negative volume, but didn't panic")
		}
	}()

	calculateCellGeometry(vertices, vertexIndices, faceStarts)
}

//
// Test deriveNeighbours
//

func TestDeriveNeighbours_SingleTriangle(t *testing.T) {
	// Single triangle - all faces should be boundaries
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	neighbours := deriveNeighbours(vertexIndices, faceStarts)

	for i, n := range neighbours {
		if n != -1 {
			t.Errorf("face %d should be boundary (neighbour=-1), got %d", i, n)
		}
	}
}

func TestDeriveNeighbours_TwoTrianglesSharedEdge(t *testing.T) {
	// Two triangles sharing edge 1-2:
	// Triangle 0: vertices 0,1,2
	// Triangle 1: vertices 1,3,2
	vertexIndices := []int{0, 1, 2, 1, 3, 2}
	faceStarts := []int{0, 3, 6}

	neighbours := deriveNeighbours(vertexIndices, faceStarts)

	// Triangle 0:
	// Face 0 (edge 0-1): boundary
	// Face 1 (edge 1-2): internal, neighbour=1
	// Face 2 (edge 2-0): boundary
	if neighbours[0] != -1 {
		t.Errorf("face 0 should be boundary, got neighbour %d", neighbours[0])
	}
	if neighbours[1] != 1 {
		t.Errorf("face 1 should have neighbour 1, got %d", neighbours[1])
	}
	if neighbours[2] != -1 {
		t.Errorf("face 2 should be boundary, got neighbour %d", neighbours[2])
	}

	// Triangle 1:
	// Face 0 (edge 1-3): boundary
	// Face 1 (edge 3-2): boundary
	// Face 2 (edge 2-1): internal, neighbour=0
	if neighbours[3] != -1 {
		t.Errorf("face 3 should be boundary, got neighbour %d", neighbours[3])
	}
	if neighbours[4] != -1 {
		t.Errorf("face 4 should be boundary, got neighbour %d", neighbours[4])
	}
	if neighbours[5] != 0 {
		t.Errorf("face 5 should have neighbour 0, got %d", neighbours[5])
	}
}

func TestDeriveNeighbours_FourTriangleMesh(t *testing.T) {
	// Simple 2x2 mesh:
	//   2---3
	//   |\ /|
	//   | 4 |
	//   |/ \|
	//   0---1
	// Triangles: (0,1,4), (1,3,4), (3,2,4), (2,0,4)
	vertexIndices := []int{
		0, 1, 4, // tri 0
		1, 3, 4, // tri 1
		3, 2, 4, // tri 2
		2, 0, 4, // tri 3
	}
	faceStarts := []int{0, 3, 6, 9, 12}

	neighbours := deriveNeighbours(vertexIndices, faceStarts)

	// Check some internal connections
	// Tri 0, face 1 (edge 1-4) should connect to tri 1
	if neighbours[1] != 1 {
		t.Errorf("tri 0 face 1 should connect to tri 1, got %d", neighbours[1])
	}

	// All boundary edges should be -1
	boundaryCount := 0
	for _, n := range neighbours {
		if n == -1 {
			boundaryCount++
		}
	}
	if boundaryCount != 4 {
		t.Errorf("expected 4 boundary faces, got %d", boundaryCount)
	}
}

//
// Test calculateInterpWeight
//

func TestCalculateInterpWeight_MidpointFace(t *testing.T) {
	// Face at midpoint between centroids
	owner := Vec2{0, 0}
	neighbour := Vec2{2, 0}
	faceV0 := Vec2{1, -0.1}
	faceV1 := Vec2{1, 0.1}

	weight := calculateInterpWeight(owner, neighbour, faceV0, faceV1)

	assertFloatEqual(t, 0.5, weight, "midpoint face weight")
}

func TestCalculateInterpWeight_FaceNearOwner(t *testing.T) {
	// Face very close to owner
	owner := Vec2{0, 0}
	neighbour := Vec2{10, 0}
	faceV0 := Vec2{0.1, -0.1}
	faceV1 := Vec2{0.1, 0.1}

	weight := calculateInterpWeight(owner, neighbour, faceV0, faceV1)

	if weight < 0 || weight > 0.2 {
		t.Errorf("face near owner should have small weight, got %.6f", weight)
	}
}

func TestCalculateInterpWeight_FaceNearNeighbour(t *testing.T) {
	// Face very close to neighbour
	owner := Vec2{0, 0}
	neighbour := Vec2{10, 0}
	faceV0 := Vec2{9.9, -0.1}
	faceV1 := Vec2{9.9, 0.1}

	weight := calculateInterpWeight(owner, neighbour, faceV0, faceV1)

	if weight < 0.8 || weight > 1.1 {
		t.Errorf("face near neighbour should have weight near 1, got %.6f", weight)
	}
}

func TestCalculateInterpWeight_OrthogonalConnection(t *testing.T) {
	// Connection and face at different angles
	owner := Vec2{0, 0}
	neighbour := Vec2{1, 1}
	faceV0 := Vec2{0.5, 0.4}
	faceV1 := Vec2{0.6, 0.5}

	weight := calculateInterpWeight(owner, neighbour, faceV0, faceV1)

	// Should be reasonable (between 0 and 1)
	if weight < 0 || weight > 1 {
		t.Errorf("weight should be in [0,1], got %.6f", weight)
	}
}

func TestCalculateInterpWeight_ParallelFallback(t *testing.T) {
	// Connection parallel to face (degenerate case)
	owner := Vec2{0, 0}
	neighbour := Vec2{2, 0}
	faceV0 := Vec2{1, 0}
	faceV1 := Vec2{3, 0} // parallel to connection

	weight := calculateInterpWeight(owner, neighbour, faceV0, faceV1)

	// Should use fallback and return reasonable value
	if weight < 0 || weight > 1 {
		t.Errorf("parallel case should return weight in [0,1], got %.6f", weight)
	}
}

//
// Test buildSegmentMarkerMap
//

func TestBuildSegmentMarkerMap_BasicMarkers(t *testing.T) {
	output := &triangle.Output{
		Segments:       []int{0, 1, 1, 2, 2, 0},
		SegmentMarkers: []int{10, 20, 30},
	}
	indexMap := []int{0, 1, 2} // identity mapping

	markers := buildSegmentMarkerMap(output, indexMap)

	// Check markers are correctly assigned to canonical edges
	if markers[[2]int{0, 1}] != 10 {
		t.Errorf("edge (0,1) should have marker 10")
	}
	if markers[[2]int{1, 2}] != 20 {
		t.Errorf("edge (1,2) should have marker 20")
	}
	if markers[[2]int{0, 2}] != 30 {
		t.Errorf("edge (0,2) should have marker 30")
	}
}

func TestBuildSegmentMarkerMap_WithIndexRemapping(t *testing.T) {
	output := &triangle.Output{
		Segments:       []int{0, 1, 2, 3},
		SegmentMarkers: []int{100, 200},
	}
	// Deduplication mapped vertices
	indexMap := []int{0, 1, 1, 2} // vertex 1 and 2 were duplicates

	markers := buildSegmentMarkerMap(output, indexMap)

	// After remapping: segment (0,1) -> (0,1), segment (2,3) -> (1,2)
	if markers[[2]int{0, 1}] != 100 {
		t.Errorf("remapped edge (0,1) should have marker 100")
	}
	if markers[[2]int{1, 2}] != 200 {
		t.Errorf("remapped edge (1,2) should have marker 200")
	}
}

func TestBuildSegmentMarkerMap_MissingMarkers(t *testing.T) {
	output := &triangle.Output{
		Segments:       []int{0, 1, 1, 2},
		SegmentMarkers: []int{}, // no markers
	}
	indexMap := []int{0, 1, 2}

	markers := buildSegmentMarkerMap(output, indexMap)

	// Should create map but with no entries (or default 0)
	if len(markers) != 0 {
		t.Errorf("expected empty marker map, got %d entries", len(markers))
	}
}

//
// Test buildFaceMarkers
//

func TestBuildFaceMarkers_SingleTriangle(t *testing.T) {
	// Triangle with all edges marked
	segmentMarkers := map[[2]int]int{
		{0, 1}: 10,
		{1, 2}: 20,
		{0, 2}: 30,
	}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	markers := buildFaceMarkers(segmentMarkers, vertexIndices, faceStarts)

	if markers[0] != 10 { // face 0 is edge 0->1
		t.Errorf("face 0 should have marker 10, got %d", markers[0])
	}
	if markers[1] != 20 { // face 1 is edge 1->2
		t.Errorf("face 1 should have marker 20, got %d", markers[1])
	}
	if markers[2] != 30 { // face 2 is edge 2->0
		t.Errorf("face 2 should have marker 30, got %d", markers[2])
	}
}

func TestBuildFaceMarkers_PartialMarking(t *testing.T) {
	// Only some edges marked (internal edges unmarked)
	segmentMarkers := map[[2]int]int{
		{0, 1}: 100,
		// edge (1,2) not marked (internal)
		{0, 2}: 200,
	}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	markers := buildFaceMarkers(segmentMarkers, vertexIndices, faceStarts)

	if markers[0] != 100 {
		t.Errorf("face 0 should have marker 100, got %d", markers[0])
	}
	if markers[1] != 0 {
		t.Errorf("face 1 (internal) should have marker 0, got %d", markers[1])
	}
	if markers[2] != 200 {
		t.Errorf("face 2 should have marker 200, got %d", markers[2])
	}
}

//
// Integration test: buildConnectionGeometry
//

func TestBuildConnectionGeometry_SingleTriangle(t *testing.T) {
	vertices := []Vec2{{0, 0}, {1, 0}, {0, 1}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}
	centroids := []Vec2{{1.0 / 3.0, 1.0 / 3.0}}
	faceMarkers := []int{10, 20, 30}

	connections, faceAreas, faceNormals, faceCentroids, _, interpWeights :=
		buildConnectionGeometry(vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	// Should have 3 boundary connections
	if len(connections) != 3 {
		t.Fatalf("expected 3 connections, got %d", len(connections))
	}

	// All should be boundaries
	for i, conn := range connections {
		if conn.Neighbour >= 0 {
			t.Errorf("connection %d should be boundary, got neighbour %d", i, conn.Neighbour)
		}
		if interpWeights[i] != 1.0 {
			t.Errorf("boundary connection %d should have weight 1.0, got %.6f", i, interpWeights[i])
		}
	}

	// Check face areas (sides of right triangle: 1, sqrt(2), 1)
	expectedAreas := []float64{1.0, math.Sqrt(2.0), 1.0}
	for i, expected := range expectedAreas {
		assertFloatEqual(t, expected, faceAreas[i], "face area "+string(rune('0'+i)))
	}

	// Check normals are unit length
	for i, n := range faceNormals {
		length := math.Sqrt(n.X*n.X + n.Y*n.Y)
		assertFloatEqual(t, 1.0, length, "normal length for face "+string(rune('0'+i)))
	}

	// Check face centroids are midpoints
	expectedCentroids := []Vec2{
		{0.5, 0.0}, // midpoint of (0,0)-(1,0)
		{0.5, 0.5}, // midpoint of (1,0)-(0,1)
		{0.0, 0.5}, // midpoint of (0,1)-(0,0)
	}
	for i, expected := range expectedCentroids {
		assertVec2Equal(t, expected, faceCentroids[i], "face centroid "+string(rune('0'+i)))
	}
}

func TestBuildConnectionGeometry_TwoTrianglesInternal(t *testing.T) {
	vertices := []Vec2{
		{0, 0}, {1, 0}, {0.5, 0.5}, {1, 1},
	}
	// Two triangles: (0,1,2) and (1,3,2)
	vertexIndices := []int{0, 1, 2, 1, 3, 2}
	faceStarts := []int{0, 3, 6}
	centroids := []Vec2{{0.5, 0.167}, {0.833, 0.5}} // approximate
	faceMarkers := []int{10, 0, 20, 30, 40, 0}      // internal faces have marker 0

	connections, _, _, _, _, interpWeights :=
		buildConnectionGeometry(vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	// Should have 5 connections total (4 boundary + 1 internal, but internal stored once)
	// Internal face between tri 0 and tri 1 only stored once (by lower index)
	internalCount := 0
	boundaryCount := 0
	for i, conn := range connections {
		if conn.Neighbour >= 0 {
			internalCount++
			// Internal connections should have weight in (0, 1)
			if interpWeights[i] <= 0 || interpWeights[i] >= 1 {
				t.Errorf("internal connection %d has invalid weight %.6f", i, interpWeights[i])
			}
		} else {
			boundaryCount++
		}
	}

	if internalCount != 1 {
		t.Errorf("expected 1 internal connection, got %d", internalCount)
	}
	if boundaryCount != 4 {
		t.Errorf("expected 4 boundary connections, got %d", boundaryCount)
	}
}

func TestBuildConnectionGeometry_NormalOrientation(t *testing.T) {
	// Single triangle - verify normals point outward from centroid
	vertices := []Vec2{{0, 0}, {1, 0}, {0, 1}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}
	centroids := []Vec2{{1.0 / 3.0, 1.0 / 3.0}}
	faceMarkers := []int{1, 1, 1}

	_, _, faceNormals, faceCentroids, _, _ :=
		buildConnectionGeometry(vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	centroid := centroids[0]

	for i := range faceNormals {
		// Vector from centroid to face centroid
		toFace := Vec2{
			X: faceCentroids[i].X - centroid.X,
			Y: faceCentroids[i].Y - centroid.Y,
		}

		// Normal should point in same direction
		dot := faceNormals[i].X*toFace.X + faceNormals[i].Y*toFace.Y
		if dot < 0 {
			t.Errorf("face %d normal points inward (dot=%.6f)", i, dot)
		}
	}
}

//
// Property-based tests
//

func TestMeshProperties_VolumeConservation(t *testing.T) {
	// Create a simple square domain meshed into triangles
	// Total area should sum correctly
	vertices := []Vec2{
		{0, 0}, {1, 0}, {1, 1}, {0, 1}, {0.5, 0.5}, // center vertex
	}
	// Four triangles around center
	vertexIndices := []int{
		0, 1, 4,
		1, 2, 4,
		2, 3, 4,
		3, 0, 4,
	}
	faceStarts := []int{0, 3, 6, 9, 12}

	volumes, _ := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	totalVolume := 0.0
	for _, v := range volumes {
		totalVolume += v
	}

	expectedVolume := 1.0 // unit square
	assertFloatEqual(t, expectedVolume, totalVolume, "total mesh volume")
}

func TestMeshProperties_AllNormalsUnitLength(t *testing.T) {
	vertices := []Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	vertexIndices := []int{0, 1, 2, 2, 3, 0} // two triangles
	faceStarts := []int{0, 3, 6}
	centroids := []Vec2{{2.0 / 3.0, 1.0 / 3.0}, {1.0 / 3.0, 2.0 / 3.0}}
	faceMarkers := make([]int, len(vertexIndices))

	_, _, faceNormals, _, _, _ :=
		buildConnectionGeometry(vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	for i, n := range faceNormals {
		length := math.Sqrt(n.X*n.X + n.Y*n.Y)
		assertFloatEqual(t, 1.0, length, "normal unit length for face "+string(rune('0'+i)))
	}
}

func TestMeshProperties_SymmetricNeighbours(t *testing.T) {
	// Two triangles - if A is neighbour of B, B should be neighbour of A
	vertexIndices := []int{0, 1, 2, 1, 3, 2}
	faceStarts := []int{0, 3, 6}

	neighbours := deriveNeighbours(vertexIndices, faceStarts)

	// Build reverse map: which face connects to which
	for faceIdx, neighbour := range neighbours {
		if neighbour >= 0 {
			// Find the corresponding face in the neighbour cell
			neighbourStart := faceStarts[neighbour]
			neighbourEnd := faceStarts[neighbour+1]

			found := false
			for nFace := neighbourStart; nFace < neighbourEnd; nFace++ {
				if neighbours[nFace] == faceIdx/(faceStarts[1]-faceStarts[0]) {
					found = true
					break
				}
			}

			if !found {
				t.Errorf("face %d has neighbour %d, but neighbour doesn't connect back",
					faceIdx, neighbour)
			}
		}
	}
}

//
// Edge cases and error conditions
//

func TestEdgeCase_EmptyMesh(t *testing.T) {
	vertices := []Vec2{}
	vertexIndices := []int{}
	faceStarts := []int{0}

	volumes, centroids := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	if len(volumes) != 0 {
		t.Errorf("empty mesh should have 0 volumes")
	}
	if len(centroids) != 0 {
		t.Errorf("empty mesh should have 0 centroids")
	}
}

func TestEdgeCase_VerySmallTriangle(t *testing.T) {
	// Tiny triangle to test numerical stability
	scale := 1e-6
	vertices := []Vec2{{0, 0}, {scale, 0}, {0, scale}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	volumes, _ := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	expectedArea := 0.5 * scale * scale
	if math.Abs(volumes[0]-expectedArea)/expectedArea > 1e-6 {
		t.Errorf("small triangle area calculation unstable: expected %.2e, got %.2e",
			expectedArea, volumes[0])
	}
}

func TestEdgeCase_VeryLargeTriangle(t *testing.T) {
	// Huge triangle
	scale := 1e6
	vertices := []Vec2{{0, 0}, {scale, 0}, {0, scale}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	volumes, _ := calculateCellGeometry(vertices, vertexIndices, faceStarts)

	expectedArea := 0.5 * scale * scale
	relError := math.Abs(volumes[0]-expectedArea) / expectedArea
	if relError > 1e-6 {
		t.Errorf("large triangle area calculation unstable: relative error %.2e", relError)
	}
}
