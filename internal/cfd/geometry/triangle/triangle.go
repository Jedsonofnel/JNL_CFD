package triangle

/*
#cgo CFLAGS: -I./src -I./src/private
#cgo LDFLAGS: -lm
#include "src/triangle_api.c"
#include "src/triangle.c"
#include "src/predicates.c"
#include "src/triangle_helper.c"
#include "src/triangle_io.c"
#include "src/acute.c"
#include "src/eps_writer.c"
*/
import "C"

type Input struct {
	Points         []C.REAL // [x0, y0, x1, y1, ...]
	Segments       []C.int  // [p0, p1, p2, p3, ...]
	SegmentMarkers []C.int  // [marker0, marker1, ...]
	Regions        []C.REAL // [x, y, id, area, ...]
	Holes          []C.REAL // [hx, hy, ...]
}

type Output struct {
	Points             []C.REAL // All vertices (input + new)
	Triangles          []C.int  // [v0, v1, v2, ...] triplets
	Neighbors          []C.int  // [-1 or neighbor cell index]
	Segments           []C.int  // Boundary segments
	SegmentMarkers     []C.int  // Boundary markers
	TriangleAttributes []C.REAL // Region ID per triangle
}

//
// Handles all Triangle.c interrop
//

func Triangulate(input Input, options string) (*Output, error) {
	// 1. Allocate C memory for input
	// 2. Call triangle C library
	// 3. Copy output to Go slices (C types)
	// 4. Free C memory
	// 5. Return output
	return nil, nil
}
