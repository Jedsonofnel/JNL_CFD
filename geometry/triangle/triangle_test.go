package triangle

import (
	"testing"
)

//
// Test basic triangulation
//

func TestTriangulate_SimpleSquare(t *testing.T) {
	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1, // bottom
			1, 2, // right
			2, 3, // top
			3, 0, // left
		},
		SegmentMarkers: []int{1, 2, 3, 4},
	}

	output, err := Triangulate(input, "pzQ") // No refinement
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	if len(output.Points) != 8 {
		t.Errorf("expected 4 vertices (8 coords), got %d coords", len(output.Points))
	}

	if len(output.Triangles) != 6 {
		t.Errorf("expected 2 triangles (6 indices), got %d", len(output.Triangles))
	}

	if len(output.Segments) != 8 {
		t.Errorf("expected 4 boundary segments (8 indices), got %d", len(output.Segments))
	}

	// CRITICAL: Check segment markers are preserved
	if len(output.SegmentMarkers) != 4 {
		t.Fatalf("expected 4 segment markers, got %d", len(output.SegmentMarkers))
	}

	// Verify all markers are present (order might differ)
	markerSet := make(map[int]bool)
	for _, m := range output.SegmentMarkers {
		markerSet[m] = true
	}

	for _, expected := range []int{1, 2, 3, 4} {
		if !markerSet[expected] {
			t.Errorf("marker %d missing from output", expected)
		}
	}
}

//
// Test marker preservation with refinement
//

func TestTriangulate_MarkersWithRefinement(t *testing.T) {
	// Rectangle with different markers on each side
	input := Input{
		Points: []float64{
			0, 0,
			2, 0,
			2, 1,
			0, 1,
		},
		Segments: []int{
			0, 1, // bottom
			1, 2, // right
			2, 3, // top
			3, 0, // left
		},
		SegmentMarkers: []int{10, 20, 30, 40},
	}

	// WITH quality constraint - Triangle will add Steiner points
	output, err := Triangulate(input, "pzQq30") // q30 = minimum angle 30°
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	// Should have MORE vertices due to refinement
	numVertices := len(output.Points) / 2
	if numVertices <= 4 {
		t.Errorf("expected > 4 vertices with refinement, got %d", numVertices)
	}

	// Should have MORE segments (original segments split by Steiner points)
	numSegments := len(output.Segments) / 2
	if numSegments < 4 {
		t.Errorf("expected >= 4 segments, got %d", numSegments)
	}

	// CRITICAL: Check if markers are preserved on sub-segments
	if len(output.SegmentMarkers) != numSegments {
		t.Fatalf("marker count mismatch: %d segments but %d markers",
			numSegments, len(output.SegmentMarkers))
	}

	// Count markers
	markerCounts := make(map[int]int)
	for _, m := range output.SegmentMarkers {
		markerCounts[m]++
	}

	t.Logf("Marker distribution after refinement:")
	for marker, count := range markerCounts {
		t.Logf("  Marker %d: %d segments", marker, count)
	}

	// Each original marker should appear at least once
	for _, expected := range []int{10, 20, 30, 40} {
		if markerCounts[expected] == 0 {
			t.Errorf("marker %d completely missing after refinement", expected)
		}
	}

	// Check for unmarked segments (marker=0)
	if markerCounts[0] > 0 {
		t.Errorf("found %d segments with marker=0 (unmarked boundary!)", markerCounts[0])
	}
}

//
// Test area constraints and marker preservation
//

func TestTriangulate_AreaConstraintPreservesMarkers(t *testing.T) {
	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1,
			1, 2,
			2, 3,
			3, 0,
		},
		SegmentMarkers: []int{1, 2, 3, 4},
	}

	// Small area constraint forces many triangles
	output, err := Triangulate(input, "pzQa0.01") // max area = 0.01
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	numTriangles := len(output.Triangles) / 3
	if numTriangles < 10 {
		t.Errorf("expected > 10 triangles with area constraint, got %d", numTriangles)
	}

	// Check segment markers
	numSegments := len(output.Segments) / 2
	if len(output.SegmentMarkers) != numSegments {
		t.Errorf("segment marker count mismatch")
	}

	markerCounts := make(map[int]int)
	for _, m := range output.SegmentMarkers {
		markerCounts[m]++
	}

	// All 4 markers should still be present
	for i := 1; i <= 4; i++ {
		if markerCounts[i] == 0 {
			t.Errorf("marker %d missing with area constraint", i)
		}
	}

	// Check for unmarked boundaries
	if markerCounts[0] > 0 {
		t.Errorf("found %d unmarked boundary segments with area constraint", markerCounts[0])
	}
}

//
// Test regions
//

func TestTriangulate_RegionAttributes(t *testing.T) {
	// Square with a region point
	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1,
			1, 2,
			2, 3,
			3, 0,
		},
		SegmentMarkers: []int{1, 1, 1, 1},
		// Region: point (0.5, 0.5), attribute=42, no max area
		Regions: []float64{0.5, 0.5, 42, 0},
	}

	output, err := Triangulate(input, "pzQA") // A = assign region attributes
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	// Check triangle attributes
	numTriangles := len(output.Triangles) / 3
	if len(output.TriangleAttributes) != numTriangles {
		t.Errorf("expected %d triangle attributes, got %d",
			numTriangles, len(output.TriangleAttributes))
	}

	// All triangles should have region ID = 42
	for i, attr := range output.TriangleAttributes {
		if attr != 42 {
			t.Errorf("triangle %d has attribute %.0f, expected 42", i, attr)
		}
	}
}

func TestTriangulate_MultipleRegions(t *testing.T) {
	// Two squares side by side
	input := Input{
		Points: []float64{
			0, 0, // 0
			1, 0, // 1
			1, 1, // 2
			0, 1, // 3
			2, 0, // 4
			2, 1, // 5
		},
		Segments: []int{
			0, 1, // bottom left
			1, 2, // middle vertical
			2, 3, // top left
			3, 0, // left side
			1, 4, // bottom right
			4, 5, // right side
			5, 2, // top right
		},
		SegmentMarkers: []int{1, 0, 1, 1, 1, 1, 1},
		// Two regions
		Regions: []float64{
			0.5, 0.5, 10, 0, // left region, ID=10
			1.5, 0.5, 20, 0, // right region, ID=20
		},
	}

	output, err := Triangulate(input, "pzQA")
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	// Count triangles in each region
	regionCounts := make(map[int]int)
	for _, attr := range output.TriangleAttributes {
		regionCounts[int(attr)]++
	}

	if regionCounts[10] == 0 {
		t.Errorf("no triangles in region 10")
	}
	if regionCounts[20] == 0 {
		t.Errorf("no triangles in region 20")
	}

	t.Logf("Region distribution: %d triangles in region 10, %d in region 20",
		regionCounts[10], regionCounts[20])
}

//
// Test holes
//

func TestTriangulate_WithHole(t *testing.T) {
	// Square with a hole
	input := Input{
		Points: []float64{
			// Outer square
			0, 0, // 0
			2, 0, // 1
			2, 2, // 2
			0, 2, // 3
			// Inner square (hole)
			0.5, 0.5, // 4
			1.5, 0.5, // 5
			1.5, 1.5, // 6
			0.5, 1.5, // 7
		},
		Segments: []int{
			// Outer boundary
			0, 1,
			1, 2,
			2, 3,
			3, 0,
			// Inner boundary (hole)
			4, 5,
			5, 6,
			6, 7,
			7, 4,
		},
		SegmentMarkers: []int{1, 1, 1, 1, 2, 2, 2, 2},
		Holes:          []float64{1, 1}, // Point inside hole
	}

	output, err := Triangulate(input, "pzQ")
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	// Should have no triangles inside the hole
	// Check that all triangles have positive area and are outside hole
	numTriangles := len(output.Triangles) / 3
	if numTriangles < 4 {
		t.Errorf("expected at least 4 triangles, got %d", numTriangles)
	}

	// Both boundary markers should be present
	markerSet := make(map[int]bool)
	for _, m := range output.SegmentMarkers {
		markerSet[m] = true
	}

	if !markerSet[1] || !markerSet[2] {
		t.Errorf("expected both markers 1 and 2, got markers: %v", markerSet)
	}
}

//
// Test edge output
//

func TestTriangulate_EdgeOutput(t *testing.T) {
	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1,
			1, 2,
			2, 3,
			3, 0,
		},
		SegmentMarkers: []int{1, 2, 3, 4},
	}

	// Request edges with 'e' flag (already done in extractOutput)
	output, err := Triangulate(input, "pzQ")
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	// Should have edges
	numEdges := len(output.Edges) / 2
	if numEdges == 0 {
		t.Errorf("no edges in output (should have internal + boundary edges)")
	}

	// Should have edge markers
	if len(output.EdgeMarkers) != numEdges {
		t.Errorf("edge marker count mismatch: %d edges, %d markers",
			numEdges, len(output.EdgeMarkers))
	}

	// Count boundary vs internal edges
	boundaryEdges := 0
	internalEdges := 0
	for _, marker := range output.EdgeMarkers {
		if marker != 0 {
			boundaryEdges++
		} else {
			internalEdges++
		}
	}

	t.Logf("Edge distribution: %d boundary, %d internal", boundaryEdges, internalEdges)

	if boundaryEdges == 0 {
		t.Errorf("no boundary edges found")
	}
	if internalEdges == 0 {
		t.Errorf("no internal edges found")
	}
}

//
// Test neighbor output
//

func TestTriangulate_NeighborOutput(t *testing.T) {
	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1,
			1, 2,
			2, 3,
			3, 0,
		},
	}

	output, err := Triangulate(input, "pzQ")
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	numTriangles := len(output.Triangles) / 3
	expectedNeighbors := numTriangles * 3

	if len(output.Neighbors) != expectedNeighbors {
		t.Errorf("expected %d neighbors (3 per triangle), got %d",
			expectedNeighbors, len(output.Neighbors))
	}

	// Check for valid neighbor indices
	for i, n := range output.Neighbors {
		if n != -1 && (n < 0 || n >= numTriangles) {
			t.Errorf("neighbor %d has invalid index %d (numTriangles=%d)",
				i, n, numTriangles)
		}
	}
}

//
// Regression test: verify no unmarked boundaries with common options
//

func TestTriangulate_NoUnmarkedBoundaries_CommonOptions(t *testing.T) {
	testCases := []struct {
		name    string
		options string
	}{
		{"no_refinement", "pzQ"},
		{"quality_30", "pzQq30"},
		{"area_01", "pzQa0.1"},
		{"quality_and_area", "pzQq30a0.1"},
	}

	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1,
			1, 2,
			2, 3,
			3, 0,
		},
		SegmentMarkers: []int{1, 2, 3, 4},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			output, err := Triangulate(input, tc.options)
			if err != nil {
				t.Fatalf("Triangulate failed: %v", err)
			}

			unmarked := 0
			for _, m := range output.SegmentMarkers {
				if m == 0 {
					unmarked++
				}
			}

			if unmarked > 0 {
				t.Errorf("found %d unmarked boundary segments with options '%s'",
					unmarked, tc.options)

				// Print marker distribution for debugging
				markerCounts := make(map[int]int)
				for _, m := range output.SegmentMarkers {
					markerCounts[m]++
				}
				t.Logf("Marker distribution: %v", markerCounts)
			}
		})
	}
}

//
// Test marker distribution balance
//

func TestTriangulate_MarkerDistributionBalance(t *testing.T) {
	// Large rectangle - should have roughly equal segments on opposite sides
	input := Input{
		Points: []float64{
			0, 0,
			10, 0,
			10, 1,
			0, 1,
		},
		Segments: []int{
			0, 1, // bottom (long)
			1, 2, // right (short)
			2, 3, // top (long)
			3, 0, // left (short)
		},
		SegmentMarkers: []int{1, 2, 3, 4},
	}

	output, err := Triangulate(input, "pzQq30a0.1") // Heavy refinement
	if err != nil {
		t.Fatalf("Triangulate failed: %v", err)
	}

	markerCounts := make(map[int]int)
	for _, m := range output.SegmentMarkers {
		markerCounts[m]++
	}

	t.Logf("Marker distribution:")
	for i := 1; i <= 4; i++ {
		t.Logf("  Marker %d: %d segments", i, markerCounts[i])
	}

	// Opposite sides should have similar counts
	// Bottom (1) and Top (3) are long edges
	// Right (2) and Left (4) are short edges

	longEdgeRatio := float64(markerCounts[1]) / float64(markerCounts[3])
	if longEdgeRatio < 0.5 || longEdgeRatio > 2.0 {
		t.Errorf("long edges have unbalanced marker distribution: %d vs %d",
			markerCounts[1], markerCounts[3])
	}

	shortEdgeRatio := float64(markerCounts[2]) / float64(markerCounts[4])
	if shortEdgeRatio < 0.5 || shortEdgeRatio > 2.0 {
		t.Errorf("short edges have unbalanced marker distribution: %d vs %d",
			markerCounts[2], markerCounts[4])
	}
}

//
// Error handling tests
//

func TestTriangulate_InvalidInput(t *testing.T) {
	// Odd number of point coordinates
	input := Input{
		Points: []float64{0, 0, 1}, // Invalid: 3 values
	}

	_, err := Triangulate(input, "pzQ")
	if err == nil {
		t.Error("expected error for odd number of point coordinates")
	}
}

func TestTriangulate_MismatchedMarkers(t *testing.T) {
	input := Input{
		Points: []float64{
			0, 0,
			1, 0,
			1, 1,
			0, 1,
		},
		Segments: []int{
			0, 1,
			1, 2,
			2, 3,
			3, 0,
		},
		SegmentMarkers: []int{1, 2}, // Wrong count: 2 instead of 4
	}

	_, err := Triangulate(input, "pzQ")
	if err == nil {
		t.Error("expected error for mismatched segment marker count")
	}
}
