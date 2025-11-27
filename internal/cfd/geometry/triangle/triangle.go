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

#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"errors"
	"unsafe"
)

//
// Data structures for Triangle.c
//

// Input uses pure Go types for Triangle.c public API
type Input struct {
	Points         []float64 // [x0, y0, x1, y1, ...]
	Segments       []int     // [p0, p1, p2, p3 ...]
	SegmentMarkers []int     // [marker0, marker1]
	Regions        []float64 // [x, y, id, area ...]
	Holes          []float64 // [hx, hy, ...]
}

// Output uses pure Go types for Triangle.c public API
type Output struct {
	Points             []float64 // All vertices (input + new)
	Triangles          []int     // [v0, v1, v2, ...] triplets
	Neighbors          []int     // [-1 or neighbor cell index]
	Segments           []int     // Boundary segments
	SegmentMarkers     []int     // Boundary markers
	Edges              []int     // All edges [p0, p1, ...] pairs
	EdgeMarkers        []int     // Edge markers (boundary vs interior)
	TriangleAttributes []float64 // Region ID per triangle
}

// cInput holds C-type arrays for Triangle.c
type cInput struct {
	Points         []C.REAL
	Segments       []C.int
	SegmentMarkers []C.int
	Regions        []C.REAL
	Holes          []C.REAL
}

// cOutput holds C-type arrays from Triangle.c
type cOutput struct {
	Points             []C.REAL
	Triangles          []C.int
	Neighbors          []C.int
	Segments           []C.int
	SegmentMarkers     []C.int
	Edges              []C.int
	EdgeMarkers        []C.int
	TriangleAttributes []C.REAL
}

//
// Handles all Triangle.c interrop
//

// Triangulate calls Triangle.c to generate a mesh
func Triangulate(input Input, options string) (*Output, error) {
	cInput := inputToC(input)

	// Create Triangle context
	ctx := C.triangle_context_create()
	if ctx == nil {
		return nil, errors.New("failed to create triangle context")
	}
	defer C.triangle_context_destroy(ctx)

	// Parse options string ("pq30a0.1")
	cOptions := C.CString(options)
	defer C.free(unsafe.Pointer(cOptions))

	if C.triangle_context_options(ctx, cOptions) != 0 {
		return nil, errors.New("failed to parse triangle options")
	}

	// Prepare input structure
	var tio C.triangleio
	initTriangleIO(&tio)
	defer freeTriangleIO(&tio)

	if err := populateInput(&tio, cInput); err != nil {
		return nil, err
	}

	// create mesh
	if C.triangle_mesh_create(ctx, &tio) != 0 {
		return nil, errors.New("triangle_mesh_create failed")
	}

	// copy output back
	cOutput, err := extractOutput(ctx)
	if err != nil {
		return nil, err
	}

	output := cOutputToGo(cOutput)

	return output, nil
}

//
// Go types -> C types and back
//

// inputToC converts Go types to C types for Triangle.c
func inputToC(input Input) cInput {
	ci := cInput{}

	// Convert Points: []float64 -> []C.REAL
	if len(input.Points) > 0 {
		ci.Points = make([]C.REAL, len(input.Points))
		for i, v := range input.Points {
			ci.Points[i] = C.REAL(v)
		}
	}

	// Convert Segments: []int -> []C.int
	if len(input.Segments) > 0 {
		ci.Segments = make([]C.int, len(input.Segments))
		for i, v := range input.Segments {
			ci.Segments[i] = C.int(v)
		}
	}

	// Convert SegmentMarkers: []int -> []C.int
	if len(input.SegmentMarkers) > 0 {
		ci.SegmentMarkers = make([]C.int, len(input.SegmentMarkers))
		for i, v := range input.SegmentMarkers {
			ci.SegmentMarkers[i] = C.int(v)
		}
	}

	// Convert Regions: []float64 -> []C.REAL
	if len(input.Regions) > 0 {
		ci.Regions = make([]C.REAL, len(input.Regions))
		for i, v := range input.Regions {
			ci.Regions[i] = C.REAL(v)
		}
	}

	// Convert Holes: []float64 -> []C.REAL
	if len(input.Holes) > 0 {
		ci.Holes = make([]C.REAL, len(input.Holes))
		for i, v := range input.Holes {
			ci.Holes[i] = C.REAL(v)
		}
	}

	return ci
}

// cOutputToGo converts C types from Triangle.c to Go types.
// Triangle.c uses 1-based indexing, so we convert to 0-based here
func cOutputToGo(co cOutput) *Output {
	output := &Output{}

	// Convert Points: []C.REAL -> []float64
	if len(co.Points) > 0 {
		output.Points = make([]float64, len(co.Points))
		for i, v := range co.Points {
			output.Points[i] = float64(v)
		}
	}

	// Convert Triangles: []C.int -> []int
	if len(co.Triangles) > 0 {
		output.Triangles = make([]int, len(co.Triangles))
		for i, v := range co.Triangles {
			output.Triangles[i] = int(v) - 1
		}
	}

	// Convert Neighbors: []C.int -> []int
	if len(co.Neighbors) > 0 {
		output.Neighbors = make([]int, len(co.Neighbors))
		for i, v := range co.Neighbors {
			if v == -1 {
				output.Neighbors[i] = -1
			} else {
				output.Neighbors[i] = int(v) - 1
			}
		}
	}

	// Convert Segments: []C.int -> []int
	if len(co.Segments) > 0 {
		output.Segments = make([]int, len(co.Segments))
		for i, v := range co.Segments {
			output.Segments[i] = int(v) - 1
		}
	}

	// Convert SegmentMarkers: []C.int -> []int
	if len(co.SegmentMarkers) > 0 {
		output.SegmentMarkers = make([]int, len(co.SegmentMarkers))
		for i, v := range co.SegmentMarkers {
			output.SegmentMarkers[i] = int(v)
		}
	}

	// Convert Edges: []C.int -> []int
	if len(co.Edges) > 0 {
		output.Edges = make([]int, len(co.Edges))
		for i, v := range co.Edges {
			output.Edges[i] = int(v) - 1
		}
	}

	// Convert EdgeMarkers: []C.int -> []int
	if len(co.EdgeMarkers) > 0 {
		output.EdgeMarkers = make([]int, len(co.EdgeMarkers))
		for i, v := range co.EdgeMarkers {
			output.EdgeMarkers[i] = int(v)
		}
	}

	// Convert TriangleAttributes: []C.REAL -> []float64
	if len(co.TriangleAttributes) > 0 {
		output.TriangleAttributes = make([]float64, len(co.TriangleAttributes))
		for i, v := range co.TriangleAttributes {
			output.TriangleAttributes[i] = float64(v)
		}
	}

	return output
}

//
// Memory allocation and deallocation for triangleio
//

// initTriangleIO zeros out all fields
func initTriangleIO(tio *C.triangleio) {
	C.memset(unsafe.Pointer(tio), 0, C.sizeof_triangleio)
}

// freeTriangleIO releases all C memory allocated in triangleio.
// Must use triangle_free (see triangle_api.h) for memory allocated
// by Triangle.c.
func freeTriangleIO(tio *C.triangleio) {
	if tio.pointlist != nil {
		C.triangle_free(unsafe.Pointer(tio.pointlist))
	}
	if tio.pointattributelist != nil {
		C.triangle_free(unsafe.Pointer(tio.pointattributelist))
	}
	if tio.pointmarkerlist != nil {
		C.triangle_free(unsafe.Pointer(tio.pointmarkerlist))
	}
	if tio.segmentlist != nil {
		C.triangle_free(unsafe.Pointer(tio.segmentlist))
	}
	if tio.segmentmarkerlist != nil {
		C.triangle_free(unsafe.Pointer(tio.segmentmarkerlist))
	}
	if tio.regionlist != nil {
		C.triangle_free(unsafe.Pointer(tio.regionlist))
	}
	if tio.holelist != nil {
		C.triangle_free(unsafe.Pointer(tio.holelist))
	}
	if tio.trianglelist != nil {
		C.triangle_free(unsafe.Pointer(tio.trianglelist))
	}
	if tio.triangleattributelist != nil {
		C.triangle_free(unsafe.Pointer(tio.triangleattributelist))
	}
	if tio.trianglearealist != nil {
		C.triangle_free(unsafe.Pointer(tio.trianglearealist))
	}
	if tio.neighborlist != nil {
		C.triangle_free(unsafe.Pointer(tio.neighborlist))
	}
	if tio.edgelist != nil {
		C.triangle_free(unsafe.Pointer(tio.edgelist))
	}
	if tio.edgemarkerlist != nil {
		C.triangle_free(unsafe.Pointer(tio.edgemarkerlist))
	}
}

//
// Casting cInput -> triangleio and back
//

// populateInput copies Go slices into C arrays for Triangle.c input.
// Allocates C memory that will be freed by freeTriangleIO.
func populateInput(tio *C.triangleio, input cInput) error {
	// Points: [x0, y0, x1, y1, ...]
	if len(input.Points)%2 != 0 {
		return errors.New("points must have even length (x,y pairs)")
	}
	numPoints := len(input.Points) / 2
	if numPoints > 0 {
		tio.numberofpoints = C.int(numPoints)
		tio.numberofpointattributes = 0

		size := C.size_t(len(input.Points)) * C.sizeof_REAL
		tio.pointlist = (*C.REAL)(C.malloc(size))
		if tio.pointlist == nil {
			return errors.New("failed to allocate pointlist")
		}
		C.memcpy(
			unsafe.Pointer(tio.pointlist),
			unsafe.Pointer(&input.Points[0]),
			size,
		)
	}

	// Segments: [p0, p1, p2, p3, ...]
	if len(input.Segments)%2 != 0 {
		return errors.New("segments must have even length (point index pairs)")
	}
	numSegments := len(input.Segments) / 2
	if numSegments > 0 {
		tio.numberofsegments = C.int(numSegments)

		size := C.size_t(len(input.Segments)) * C.sizeof_int
		tio.segmentlist = (*C.int)(C.malloc(size))
		if tio.segmentlist == nil {
			return errors.New("failed to allocate segmentlist")
		}
		C.memcpy(
			unsafe.Pointer(tio.segmentlist),
			unsafe.Pointer(&input.Segments[0]),
			size,
		)
	}

	// Segment markers
	if len(input.SegmentMarkers) > 0 {
		if len(input.SegmentMarkers) != numSegments {
			return errors.New("segment markers length must match number of segments")
		}

		size := C.size_t(len(input.SegmentMarkers)) * C.sizeof_int
		tio.segmentmarkerlist = (*C.int)(C.malloc(size))
		if tio.segmentmarkerlist == nil {
			return errors.New("failed to allocate segmentmarkerlist")
		}
		C.memcpy(
			unsafe.Pointer(tio.segmentmarkerlist),
			unsafe.Pointer(&input.SegmentMarkers[0]),
			size,
		)
	}

	// Regions: [x, y, attribute, max_area, ...]
	if len(input.Regions)%4 != 0 {
		return errors.New("regions must have length divisible by 4")
	}
	numRegions := len(input.Regions) / 4
	if numRegions > 0 {
		tio.numberofregions = C.int(numRegions)

		size := C.size_t(len(input.Regions)) * C.sizeof_REAL
		tio.regionlist = (*C.REAL)(C.malloc(size))
		if tio.regionlist == nil {
			return errors.New("failed to allocate regionlist")
		}
		C.memcpy(
			unsafe.Pointer(tio.regionlist),
			unsafe.Pointer(&input.Regions[0]),
			size,
		)
	}

	// Holes: [x, y, ...]
	if len(input.Holes)%2 != 0 {
		return errors.New("holes must have even length (x,y pairs)")
	}
	numHoles := len(input.Holes) / 2
	if numHoles > 0 {
		tio.numberofholes = C.int(numHoles)

		size := C.size_t(len(input.Holes)) * C.sizeof_REAL
		tio.holelist = (*C.REAL)(C.malloc(size))
		if tio.holelist == nil {
			return errors.New("failed to allocate holelist")
		}
		C.memcpy(
			unsafe.Pointer(tio.holelist),
			unsafe.Pointer(&input.Holes[0]),
			size,
		)
	}

	return nil
}

// extractOutput copies mesh data from Triangle.c context to Go slices.
// Requests both edges and neighbor information from Triangle.c.
func extractOutput(ctx *C.context) (cOutput, error) {
	var zero cOutput

	var tio C.triangleio
	initTriangleIO(&tio)
	defer freeTriangleIO(&tio)

	// Copy mesh: edges=1, neighbors=1
	if C.triangle_mesh_copy(ctx, &tio, 1, 1) != 0 {
		return zero, errors.New("triangle_mesh_copy failed")
	}

	co := cOutput{}

	// Copy points [x0, y0, x1, y1, ...]
	if tio.numberofpoints > 0 {
		numCoords := int(tio.numberofpoints) * 2
		co.Points = make([]C.REAL, numCoords)
		C.memcpy(
			unsafe.Pointer(&co.Points[0]),
			unsafe.Pointer(tio.pointlist),
			C.size_t(numCoords)*C.sizeof_REAL,
		)
	}

	// Copy triangles (numberofcorners vertices per triangle, typically 3)
	if tio.numberoftriangles > 0 {
		numIndices := int(tio.numberoftriangles) * int(tio.numberofcorners)
		co.Triangles = make([]C.int, numIndices)
		C.memcpy(
			unsafe.Pointer(&co.Triangles[0]),
			unsafe.Pointer(tio.trianglelist),
			C.size_t(numIndices)*C.sizeof_int,
		)
	}

	// Copy neighbors (3 per triangle)
	if tio.neighborlist != nil && tio.numberoftriangles > 0 {
		numNeighbors := int(tio.numberoftriangles) * 3
		co.Neighbors = make([]C.int, numNeighbors)
		C.memcpy(
			unsafe.Pointer(&co.Neighbors[0]),
			unsafe.Pointer(tio.neighborlist),
			C.size_t(numNeighbors)*C.sizeof_int,
		)
	}

	// Copy segments
	if tio.numberofsegments > 0 {
		numSegIndices := int(tio.numberofsegments) * 2
		co.Segments = make([]C.int, numSegIndices)
		C.memcpy(
			unsafe.Pointer(&co.Segments[0]),
			unsafe.Pointer(tio.segmentlist),
			C.size_t(numSegIndices)*C.sizeof_int,
		)

		if tio.segmentmarkerlist != nil {
			co.SegmentMarkers = make([]C.int, tio.numberofsegments)
			C.memcpy(
				unsafe.Pointer(&co.SegmentMarkers[0]),
				unsafe.Pointer(tio.segmentmarkerlist),
				C.size_t(tio.numberofsegments)*C.sizeof_int,
			)
		}
	}

	// Copy edges (output only, requested with edges=1)
	if tio.numberofedges > 0 && tio.edgelist != nil {
		numEdgeIndices := int(tio.numberofedges) * 2
		co.Edges = make([]C.int, numEdgeIndices)
		C.memcpy(
			unsafe.Pointer(&co.Edges[0]),
			unsafe.Pointer(tio.edgelist),
			C.size_t(numEdgeIndices)*C.sizeof_int,
		)

		if tio.edgemarkerlist != nil {
			co.EdgeMarkers = make([]C.int, tio.numberofedges)
			C.memcpy(
				unsafe.Pointer(&co.EdgeMarkers[0]),
				unsafe.Pointer(tio.edgemarkerlist),
				C.size_t(tio.numberofedges)*C.sizeof_int,
			)
		}
	}

	// Copy triangle attributes (region IDs)
	if tio.triangleattributelist != nil && tio.numberoftriangles > 0 {
		numAttrs := int(tio.numberoftriangles) * int(tio.numberoftriangleattributes)
		if numAttrs > 0 {
			co.TriangleAttributes = make([]C.REAL, numAttrs)
			C.memcpy(
				unsafe.Pointer(&co.TriangleAttributes[0]),
				unsafe.Pointer(tio.triangleattributelist),
				C.size_t(numAttrs)*C.sizeof_REAL,
			)
		}
	}

	return co, nil
}
