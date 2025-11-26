package geometry

import (
	"errors"
)

//
// Domain definition for meshing
//

type Domain struct {
	shapes        []Shape
	nextRegionID  int
	nextMarker    int
	regionNames   map[int]string
	boundaryNames map[int]string
}

// Shape interface - extensible to circles, polygons, etc.
type Shape interface {
	Bounds() (minX, minY, maxX, maxY float64)
	Intersects(other Shape) bool
	ToPSLG(pointOffset int) (points []Vec2, segments []Segment, region *Region)
}

type Segment struct {
	P0, P1 int // point indices
	Marker int
}

type Region struct {
	Point   Vec2
	ID      int
	MaxArea float64
}

func NewDomain() *Domain {
	return &Domain{
		shapes:        make([]Shape, 0),
		nextRegionID:  1,
		nextMarker:    1,
		regionNames:   make(map[int]string),
		boundaryNames: make(map[int]string),
	}
}

func (d *Domain) AddShape(shape Shape, regionName, boundaryName string) error {
	for _, existing := range d.shapes {
		if shape.Intersects(existing) {
			return errors.New("shape intersection error")
		}
	}

	d.shapes = append(d.shapes, shape)
	d.regionNames[d.nextRegionID] = regionName
	d.boundaryNames[d.nextMarker] = boundaryName

	d.nextRegionID++
	d.nextMarker++

	return nil
}

func (d *Domain) Bounds() (minX, minY, maxX, maxY float64) {
	if len(d.shapes) == 0 {
		return 0, 0, 1, 1
	}

	minX, minY, maxX, maxY = d.shapes[0].Bounds()
	for _, shape := range d.shapes[1:] {
		x0, y0, x1, y1 := shape.Bounds()
		minX = min(minX, x0)
		minY = min(minY, y0)
		maxX = max(maxX, x1)
		maxY = max(maxY, y1)
	}
	return
}

func (d *Domain) ToPSLG() PSLG {
	var allPoints []Vec2
	var allSegments []Segment
	var allRegions []Region

	pointOffset := 0
	for _, shape := range d.shapes {
		pts, segs, reg := shape.ToPSLG(pointOffset)
		allPoints = append(allPoints, pts...)
		allSegments = append(allSegments, segs...)
		if reg != nil {
			allRegions = append(allRegions, *reg)
		}
		pointOffset += len(pts)
	}

	return PSLG{
		Points:   allPoints,
		Segments: allSegments,
		Regions:  allRegions,
	}
}

//
// Rectangle shape implementation
//

// It's kinda like a square but different
type Rectangle struct {
	X, Y, W, H     float64
	regionID       int
	boundaryMarker int
}

func (r *Rectangle) Bounds() (minX, minY, maxX, maxY float64) {
	return r.X, r.Y, r.X + r.W, r.Y + r.H
}

func (r *Rectangle) Intersects(other Shape) bool {
	x0, y0, x1, y1 := r.Bounds()
	ox0, oy0, ox1, oy1 := other.Bounds()

	// AABB intersection test
	return !(x1 < ox0 || x0 > ox1 || y1 < oy0 || y0 > oy1)
}

func (r *Rectangle) ToPSLG(pointOffset int) ([]Vec2, []Segment, *Region) {
	points := []Vec2{
		{r.X, r.Y},
		{r.X + r.W, r.Y},
		{r.X + r.W, r.Y + r.H},
		{r.X, r.Y + r.H},
	}

	segments := []Segment{
		{pointOffset + 0, pointOffset + 1, r.boundaryMarker},
		{pointOffset + 1, pointOffset + 2, r.boundaryMarker},
		{pointOffset + 2, pointOffset + 3, r.boundaryMarker},
		{pointOffset + 3, pointOffset + 0, r.boundaryMarker},
	}

	// Region label point (center)
	region := &Region{
		Point:   Vec2{r.X + r.W/2, r.Y + r.H/2},
		ID:      r.regionID,
		MaxArea: 0, // TODO: consider this
	}

	return points, segments, region
}
