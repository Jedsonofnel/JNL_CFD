package geometry

import (
	"errors"
	"slices"
)

//
// Domain definition for meshing
//

const rootShapeLayer = -1

type Domain struct {
	shapes        []Shape
	layers        []int // layer index for each shape
	parents       []int // parent shape index (-1 if no parent)
	nextRegionID  int
	nextMarker    int
	regionNames   map[int]string
	boundaryNames map[int]string
}

// Shape interface - extensible to circles, polygons, etc.
type Shape interface {
	Bounds() (minX, minY, maxX, maxY float64)
	Intersects(other Shape) bool
	Contains(point Vec2) bool
	Area() float64
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
		layers:        make([]int, 0),
		parents:       make([]int, 0),
		nextRegionID:  1,
		nextMarker:    1,
		regionNames:   make(map[int]string),
		boundaryNames: make(map[int]string),
	}
}

func (d *Domain) AddShape(shape Shape, regionName, boundaryName string) error {
	invalid := slices.ContainsFunc(d.shapes, func(existing Shape) bool {
		if shape.Intersects(existing) && !isValidContainment(shape, existing) {
			return true
		}
		return false
	})

	if invalid {
		return errors.New("shape intersection error")
	}

	// Insert in sorted order by area (descending)
	area := shape.Area()
	insertIdx := len(d.shapes)
	for i, s := range d.shapes {
		if area > s.Area() {
			insertIdx = i
			break
		}
	}

	// Insert at position
	d.shapes = append(d.shapes[:insertIdx],
		append([]Shape{shape}, d.shapes[insertIdx:]...)...)

	d.layers = append(d.layers[:insertIdx],
		append([]int{0}, d.layers[insertIdx:]...)...)
	d.parents = append(d.parents[:insertIdx],
		append([]int{-1}, d.parents[insertIdx:]...)...)

	d.regionNames[d.nextRegionID] = regionName
	d.boundaryNames[d.nextMarker] = boundaryName

	d.nextRegionID++
	d.nextMarker++

	return nil
}

// isValidContainment checks if one shape fully contains the other
func isValidContainment(a, b Shape) bool {
	ax0, ay0, ax1, ay1 := a.Bounds()
	bx0, by0, bx1, by1 := b.Bounds()

	// Does a contain b?
	aContainsB := ax0 <= bx0 && ay0 <= by0 && ax1 >= bx1 && ay1 >= by1
	// Does b contain a?
	bContainsA := bx0 <= ax0 && by0 <= ay0 && bx1 >= ax1 && by1 >= ay1

	return aContainsB || bContainsA
}

// ComputeLayers calculates the containment hierarchy after all shapes are added
func (d *Domain) ComputeLayers() {
	n := len(d.shapes)

	for i := range d.layers {
		d.layers[i] = 0
		d.parents[i] = rootShapeLayer
	}

	for i := 1; i < n; i++ {
		minX, minY, maxX, maxY := d.shapes[i].Bounds()
		centerX := (minX + maxX) / 2
		centerY := (minY + maxY) / 2
		center := Vec2{centerX, centerY}

		// Look for parent among earlier (larger) shapes
		for j := 0; j < i; j++ {
			if d.shapes[j].Contains(center) {
				d.parents[i] = j
				d.layers[i] = d.layers[j] + 1
				break
			}
		}
	}
}

func (d *Domain) GetLayer(idx int) int {
	if idx < 0 || idx >= len(d.layers) {
		return -1
	}
	return d.layers[idx]
}

func (d *Domain) GetParent(idx int) int {
	if idx < 0 || idx >= len(d.parents) {
		return -1
	}
	return d.parents[idx]
}

func (d *Domain) Shapes() []Shape {
	return d.shapes
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

func NewRectangle(x, y, w, h float64) *Rectangle {
	return &Rectangle{
		X: x,
		Y: y,
		W: w,
		H: h,
	}
}

func (r *Rectangle) Bounds() (minX, minY, maxX, maxY float64) {
	return r.X, r.Y, r.X + r.W, r.Y + r.H
}

func (r *Rectangle) Intersects(other Shape) bool {
	x0, y0, x1, y1 := r.Bounds()
	ox0, oy0, ox1, oy1 := other.Bounds()

	// AABB intersection test
	return !(x1 <= ox0 || x0 >= ox1 || y1 <= oy0 || y0 >= oy1)
}

func (r *Rectangle) Contains(point Vec2) bool {
	return point.X >= r.X && point.X <= r.X+r.W &&
		point.Y >= r.Y && point.Y <= r.Y+r.H
}

func (r *Rectangle) Area() float64 {
	return r.W * r.H
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
