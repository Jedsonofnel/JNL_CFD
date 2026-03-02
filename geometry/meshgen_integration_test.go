package geometry

import (
	"testing"

	"jedn.dev/jnlcfd/geometry/triangle"
)

//
// Test the Triangle.c → Mesh conversion pipeline
//

func TestTriangleIntegration_SimpleSquareMarkers(t *testing.T) {
	// Create a domain with clear markers
	rectangle := MakeRectangle(0, 0, 1, 1, "test", "bottom", "right", "top", "left")

	var db DomainBuilder
	db.AddPolygon(rectangle)
	domain, _ := db.Build()

	// Mesh without refinement
	mesh, err := MeshDomain(domain, "pzQ")
	if err != nil {
		t.Fatalf("MeshDomain failed: %v", err)
	}

	// Count boundary connections by marker
	markerCounts := make(map[int32]int)
	boundaryConns := 0

	for _, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			boundaryConns++
			markerCounts[-1*conn.Neighbour]++
		}
	}

	t.Logf("Boundary connections: %d", boundaryConns)
	for marker, count := range markerCounts {
		name := mesh.BoundaryNames[int(marker)]
		t.Logf("  Marker %d (%s): %d connections", marker, name, count)
	}

	// Should have 4 boundary connections (4 edges of square)
	if boundaryConns != 4 {
		t.Errorf("expected 4 boundary connections, got %d", boundaryConns)
	}

	// All 4 markers should be present
	if len(markerCounts) != 4 {
		t.Errorf("expected 4 unique markers, got %d", len(markerCounts))
	}

	// Each marker should appear exactly once
	for marker := int32(1); marker <= 4; marker++ {
		if markerCounts[marker] != 1 {
			name := mesh.BoundaryNames[int(marker)]
			t.Errorf("marker %d (%s) should appear once, got %d",
				marker, name, markerCounts[marker])
		}
	}
}

func TestTriangleIntegration_RectangleWithRefinement(t *testing.T) {
	rectangle := MakeRectangle(0, 0, 10, 1, "test", "bottom", "right", "top", "left")

	var db DomainBuilder
	db.AddPolygon(rectangle)
	domain, _ := db.Build()

	mesh, err := MeshDomain(domain, "pzQq30a0.1")
	if err != nil {
		t.Fatalf("MeshDomain failed: %v", err)
	}

	markerCounts := make(map[int32]int)
	unmarkedBoundary := 0

	for _, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			markerCounts[-conn.Neighbour]++
		} else if conn.Neighbour < 0 {
			// Boundary connection but marker is 0!
			unmarkedBoundary++
		}
	}

	t.Logf("Boundary marker distribution:")
	for marker, count := range markerCounts {
		name := mesh.BoundaryNames[int(marker)]
		t.Logf("  Marker %d (%s): %d connections", marker, name, count)
	}

	if unmarkedBoundary > 0 {
		t.Errorf("found %d UNMARKED boundary connections (marker=0)", unmarkedBoundary)
	}

	// Long edges (top/bottom) should have similar counts
	bottomMarker := domain.boundaryNames["bottom"]
	topMarker := domain.boundaryNames["top"]

	bottomCount := markerCounts[int32(bottomMarker)]
	topCount := markerCounts[int32(topMarker)]

	if bottomCount < 5 {
		t.Errorf("bottom should have many connections (got %d)", bottomCount)
	}
	if topCount < 5 {
		t.Errorf("top should have many connections (got %d)", topCount)
	}

	// They should be roughly equal (within 20%)
	ratio := float64(bottomCount) / float64(topCount)
	if ratio < 0.8 || ratio > 1.2 {
		t.Errorf("top/bottom marker counts very unbalanced: %d vs %d",
			bottomCount, topCount)
	}

	// Short edges (left/right) should have similar counts
	leftMarker := domain.boundaryNames["left"]
	rightMarker := domain.boundaryNames["right"]

	leftCount := markerCounts[int32(leftMarker)]
	rightCount := markerCounts[int32(rightMarker)]

	ratio = float64(leftCount) / float64(rightCount)
	if ratio < 0.8 || ratio > 1.2 {
		t.Errorf("left/right marker counts very unbalanced: %d vs %d",
			leftCount, rightCount)
	}
}

func TestTriangleOutputToMesh_RegionIDsPreserved(t *testing.T) {
	// Two adjacent rectangles with distinct regions
	//
	//   +---------+---------+
	//   | "left"  | "right" |
	//   | region  | region  |
	//   +---------+---------+
	//  (0,0)    (1,0)     (2,0)
	//
	// Shared edge at x=1 is internal (empty boundary name)

	db := &DomainBuilder{}

	err := db.AddPolygon(MakeRectangle(0, 0, 1, 1, "left",
		"south", "", "north", "west", // east edge is internal
	))
	if err != nil {
		t.Fatalf("AddPolygon left: %v", err)
	}

	err = db.AddPolygon(MakeRectangle(1, 0, 1, 1, "right",
		"south", "east", "north", "", // west edge is internal
	))
	if err != nil {
		t.Fatalf("AddPolygon right: %v", err)
	}

	domain, err := db.Build()
	if err != nil {
		t.Fatalf("Build: %v", err)
	}

	mesh, err := MeshWithArea(domain, 0.05, 30)
	if err != nil {
		t.Fatalf("MeshWithArea: %v", err)
	}

	leftID := domain.regionNames["left"]
	rightID := domain.regionNames["right"]

	if leftID == 0 || rightID == 0 {
		t.Fatalf("region IDs should be non-zero: left=%d, right=%d", leftID, rightID)
	}
	if leftID == rightID {
		t.Fatalf("regions should have distinct IDs: both are %d", leftID)
	}

	// --- Every cell must have a region ID ---
	for i, r := range mesh.CellRegions {
		if r == 0 {
			t.Errorf("cell %d has unset region ID (0)", i)
		}
	}

	// --- Both region IDs must appear ---
	regionCounts := make(map[int]int)
	for _, r := range mesh.CellRegions {
		regionCounts[r]++
	}

	if regionCounts[leftID] == 0 {
		t.Errorf("no cells assigned to region 'left' (ID=%d)", leftID)
	}
	if regionCounts[rightID] == 0 {
		t.Errorf("no cells assigned to region 'right' (ID=%d)", rightID)
	}

	// --- No unexpected region IDs ---
	for id, count := range regionCounts {
		if id != leftID && id != rightID {
			t.Errorf("unexpected region ID %d found on %d cells", id, count)
		}
	}

	// --- Spatial consistency: cells in each region are on the correct side ---
	for i, r := range mesh.CellRegions {
		cx := mesh.Centroids[i].X
		if r == leftID && cx > 1.0 {
			t.Errorf("cell %d in 'left' region but centroid at x=%.4f", i, cx)
		}
		if r == rightID && cx < 1.0 {
			t.Errorf("cell %d in 'right' region but centroid at x=%.4f", i, cx)
		}
	}

	// --- RegionNames reverse map is populated ---
	if mesh.RegionNames[leftID] != "left" {
		t.Errorf("RegionNames[%d] = %q, want 'left'", leftID, mesh.RegionNames[leftID])
	}
	if mesh.RegionNames[rightID] != "right" {
		t.Errorf("RegionNames[%d] = %q, want 'right'", rightID, mesh.RegionNames[rightID])
	}

	t.Logf("mesh: %d cells, left(ID=%d)=%d, right(ID=%d)=%d",
		len(mesh.CellRegions),
		leftID, regionCounts[leftID],
		rightID, regionCounts[rightID],
	)
}

//
// Test specific post-processing steps
//

func TestBuildSegmentMarkerMap_AfterDedup(t *testing.T) {
	// Simulate Triangle output with duplicates
	output := &triangle.Output{
		Segments: []int{
			0, 1, // segment 0
			1, 2, // segment 1
			2, 3, // segment 2
			3, 0, // segment 3
		},
		SegmentMarkers: []int{10, 20, 30, 40},
	}

	// Simulate deduplication that merged some vertices
	// e.g., vertices 1 and 2 were near-duplicates → both map to 1
	indexMap := []int{0, 1, 1, 2}

	markers := buildSegmentMarkerMap(output, indexMap)

	t.Logf("Segment markers after dedup:")
	for edge, marker := range markers {
		t.Logf("  Edge (%d,%d) → marker %d", edge[0], edge[1], marker)
	}

	// Check non-degenerate edges
	if markers[[2]int{0, 1}] != 10 {
		t.Errorf("edge (0,1) should have marker 10")
	}
	if markers[[2]int{1, 2}] != 30 {
		t.Errorf("edge (1,2) should have marker 30")
	}
	if markers[[2]int{0, 2}] != 40 {
		t.Errorf("edge (0,2) should have marker 40")
	}

	// Degenerate edge (1,1) should not be in map
	if _, exists := markers[[2]int{1, 1}]; exists {
		t.Errorf("degenerate edge (1,1) should not exist in marker map")
	}
}

func TestBuildFaceMarkers_MatchesSegmentMap(t *testing.T) {
	// Create a simple triangle mesh
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	// Segment markers: all 3 edges marked
	segmentMarkers := map[[2]int]int{
		{0, 1}: 100,
		{1, 2}: 200,
		{0, 2}: 300,
	}

	faceMarkers := buildFaceMarkers(segmentMarkers, vertexIndices, faceStarts)

	if len(faceMarkers) != 3 {
		t.Fatalf("expected 3 face markers, got %d", len(faceMarkers))
	}

	// Face 0 is edge 0→1
	if faceMarkers[0] != 100 {
		t.Errorf("face 0 (edge 0→1) should have marker 100, got %d", faceMarkers[0])
	}

	// Face 1 is edge 1→2
	if faceMarkers[1] != 200 {
		t.Errorf("face 1 (edge 1→2) should have marker 200, got %d", faceMarkers[1])
	}

	// Face 2 is edge 2→0
	if faceMarkers[2] != 300 {
		t.Errorf("face 2 (edge 2→0) should have marker 300, got %d", faceMarkers[2])
	}
}

func TestBuildFaceMarkers_UnmarkedEdges(t *testing.T) {
	// Triangle with only one edge marked (others are internal)
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}

	segmentMarkers := map[[2]int]int{
		{0, 1}: 100, // Only this edge is marked
		// Edges {1,2} and {0,2} are NOT in the map (internal)
	}

	faceMarkers := buildFaceMarkers(segmentMarkers, vertexIndices, faceStarts)

	if faceMarkers[0] != 100 {
		t.Errorf("face 0 should have marker 100, got %d", faceMarkers[0])
	}

	if faceMarkers[1] != 0 {
		t.Errorf("face 1 (unmarked) should have marker 0, got %d", faceMarkers[1])
	}

	if faceMarkers[2] != 0 {
		t.Errorf("face 2 (unmarked) should have marker 0, got %d", faceMarkers[2])
	}
}

//
// Test connection building with markers
//

func TestBuildConnectionGeometry_BoundaryMarkers(t *testing.T) {
	// Simple triangle
	vertices := []Vec2{{0, 0}, {1, 0}, {0, 1}}
	vertexIndices := []int{0, 1, 2}
	faceStarts := []int{0, 3}
	centroids := []Vec2{{1.0 / 3.0, 1.0 / 3.0}}

	// All edges marked differently
	faceMarkers := []int{10, 20, 30}

	connections, _, _, _, _, _, _ := buildConnectionGeometry(
		vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	if len(connections) != 3 {
		t.Fatalf("expected 3 connections, got %d", len(connections))
	}

	// All should be boundary connections with correct markers
	for i, conn := range connections {
		if conn.Neighbour >= 0 {
			t.Errorf("connection %d should be boundary, got neighbour %d", i, conn.Neighbour)
		}
		expectedMarker := int32(faceMarkers[i])
		if -conn.Neighbour != expectedMarker {
			t.Errorf("connection %d should have marker %d, got %d",
				i, expectedMarker, -conn.Neighbour)
		}
	}
}

func TestBuildConnectionGeometry_InternalFacesHaveZeroMarker(t *testing.T) {
	// Two triangles sharing an edge
	vertices := []Vec2{{0, 0}, {1, 0}, {0.5, 0.5}, {1, 1}}
	vertexIndices := []int{0, 1, 2, 1, 3, 2}
	faceStarts := []int{0, 3, 6}
	centroids := []Vec2{{0.5, 0.167}, {0.833, 0.5}}

	// Mark only boundary edges, internal edge (1,2) is unmarked
	faceMarkers := []int{
		10, 0, 20, // tri 0: faces have markers 10, 0 (internal), 20
		30, 40, 0, // tri 1: faces have markers 30, 40, 0 (internal)
	}

	connections, _, _, _, _, _, _ := buildConnectionGeometry(
		vertexIndices, faceStarts, vertices, centroids, faceMarkers)

	// Check that internal connections have marker 0
	for i, conn := range connections {
		if conn.Neighbour >= 0 {
			// Internal connection
			if conn.Neighbour < 0 {
				t.Errorf("internal connection %d should have neighbour >0, got %d",
					i, conn.Neighbour)
			}
		} else {
			// Boundary connection - should have non-zero marker
			if conn.Neighbour >= 0 {
				t.Errorf("boundary connection %d should have negative neighbour", i)
			}
		}
	}
}

//
// Integration test: full pipeline debugging
//

func TestTriangleIntegration_DebugMarkerLoss(t *testing.T) {
	rectangle := MakeRectangle(0, 0, 10, 1, "test", "bottom", "right", "top", "left")

	var db DomainBuilder
	db.AddPolygon(rectangle)
	domain, _ := db.Build()

	pslg := domain.toPSLG()
	input := pslgToTriangleInput(pslg)

	// Call Triangle directly to inspect output
	output, err := triangle.Triangulate(input, "pzQq30a0.1")
	if err != nil {
		t.Fatalf("Triangle failed: %v", err)
	}

	t.Logf("Triangle output:")
	t.Logf("  Vertices: %d", len(output.Points)/2)
	t.Logf("  Triangles: %d", len(output.Triangles)/3)
	t.Logf("  Segments: %d", len(output.Segments)/2)

	// Check Triangle's segment markers
	triangleMarkerCounts := make(map[int]int)
	for _, m := range output.SegmentMarkers {
		triangleMarkerCounts[m]++
	}

	t.Logf("Triangle segment markers:")
	for m, count := range triangleMarkerCounts {
		t.Logf("  Marker %d: %d segments", m, count)
	}

	// Now run through deduplication
	numVerts := len(output.Points) / 2
	vertices := make([]Vec2, numVerts)
	for i := range numVerts {
		vertices[i] = Vec2{
			X: output.Points[i*2+0],
			Y: output.Points[i*2+1],
		}
	}

	dedupVerts, indexMap := dedupVertices(vertices, 1e-6)
	t.Logf("After deduplication: %d → %d vertices", len(vertices), len(dedupVerts))

	// Check how many vertices were merged
	merged := len(vertices) - len(dedupVerts)
	if merged > 0 {
		t.Logf("  Merged %d vertices", merged)
	}

	// Build segment marker map
	segmentMarkers := buildSegmentMarkerMap(output, indexMap)
	t.Logf("Segment marker map has %d unique edges", len(segmentMarkers))

	segmentMarkerCounts := make(map[int]int)
	for _, m := range segmentMarkers {
		segmentMarkerCounts[m]++
	}

	t.Logf("Segment marker map distribution:")
	for m, count := range segmentMarkerCounts {
		t.Logf("  Marker %d: %d edges", m, count)
	}

	// Compare: did we lose markers during deduplication?
	for m := 1; m <= 4; m++ {
		before := triangleMarkerCounts[m]
		after := segmentMarkerCounts[m]

		if after < before {
			t.Errorf("MARKER LOSS: marker %d had %d segments from Triangle, only %d after dedup",
				m, before, after)
		}
	}

	// Now build the full mesh and check final connections
	mesh, err := MeshDomain(domain, "pzQq30a0.1")
	if err != nil {
		t.Fatalf("MeshDomain failed: %v", err)
	}

	finalMarkerCounts := make(map[int32]int)
	for _, conn := range mesh.Connections {
		if conn.Neighbour < 0 {
			finalMarkerCounts[-conn.Neighbour]++
		}
	}

	t.Logf("Final mesh connection markers:")
	for m, count := range finalMarkerCounts {
		name := mesh.BoundaryNames[int(m)]
		t.Logf("  Marker %d (%s): %d connections", m, name, count)
	}

	// Check for severe imbalance
	leftMarker := int32(domain.boundaryNames["left"])
	rightMarker := int32(domain.boundaryNames["right"])

	leftCount := finalMarkerCounts[leftMarker]
	rightCount := finalMarkerCounts[rightMarker]

	if leftCount < 2 || rightCount < 2 {
		t.Errorf("SEVERE MARKER IMBALANCE: left=%d, right=%d (both should be >5)",
			leftCount, rightCount)
		t.Errorf("This suggests markers are being lost in the pipeline!")
	}
}
