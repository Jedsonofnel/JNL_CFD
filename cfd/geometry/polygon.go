package geometry

import "math"

//
// Single shape type - everything is a polygon
//

type Polygon struct {
	Points     []Vec2
	Boundaries []string
	Region     string
	IsHole     bool

	// private fields
	RegionID     int
	regionCenter Vec2
	bounds       [4]float64
	boundsCache  bool
	area         float64 // for caching
}

// Bounds returns the axis-aligned bounding box
func (p *Polygon) Bounds() (minX, minY, maxX, maxY float64) {
	if p.boundsCache {
		return p.bounds[0], p.bounds[1], p.bounds[2], p.bounds[3]
	}

	if len(p.Points) == 0 {
		return 0, 0, 0, 0
	}

	minX, minY = p.Points[0].X, p.Points[0].Y
	maxX, maxY = minX, minY

	for _, pt := range p.Points[1:] {
		minX = min(minX, pt.X)
		maxX = max(maxX, pt.X)
		minY = min(minY, pt.Y)
		maxY = max(maxY, pt.Y)
	}

	p.bounds[0] = minX
	p.bounds[1] = minY
	p.bounds[2] = maxX
	p.bounds[3] = maxY

	p.boundsCache = true

	return
}

// Area calculates polygon area using shoelace formula
func (p *Polygon) Area() float64 {
	if p.area != 0 {
		return p.area
	}

	if len(p.Points) < 3 {
		return 0
	}

	var sum float64
	n := len(p.Points)

	for i := range n {
		j := (i + 1) % n
		sum += p.Points[i].X*p.Points[j].Y - p.Points[j].X*p.Points[i].Y
	}

	p.area = math.Abs(sum / 2)
	return p.area
}

// Contains checks if a point is inside the polygon using ray casting
func (p *Polygon) Contains(point Vec2) bool {
	if len(p.Points) < 3 {
		return false
	}

	// Quick bounds check
	minX, minY, maxX, maxY := p.Bounds()
	if point.X < minX || point.X > maxX || point.Y < minY || point.Y > maxY {
		return false
	}

	// Ray casting algorithm
	inside := false
	n := len(p.Points)

	for i := range n {
		j := (i + 1) % n

		vi := p.Points[i]
		vj := p.Points[j]

		// Check if ray crosses edge
		if ((vi.Y > point.Y) != (vj.Y > point.Y)) &&
			(point.X < (vj.X-vi.X)*(point.Y-vi.Y)/(vj.Y-vi.Y)+vi.X) {
			inside = !inside
		}
	}

	return inside
}

// Intersects checks if two polygons intersect (bounds check + containment test)
func (p *Polygon) Intersects(other *Polygon) bool {
	ax0, ay0, ax1, ay1 := p.Bounds()
	bx0, by0, bx1, by1 := other.Bounds()

	if ax1 <= bx0 || ax0 >= bx1 || ay1 <= by0 || ay0 >= by1 {
		return false
	}

	// Bounds intersect - check if it's valid containment
	aCenter := p.Center()
	bCenter := other.Center()

	// If one contains the other's center, it's containment (valid)
	if p.Contains(bCenter) || other.Contains(aCenter) {
		return false // Not an invalid intersection
	}

	// Bounds overlap but neither contains the other - invalid intersection
	return true
}

// center calculates the centroid (simple average of vertices)
func (p *Polygon) Center() Vec2 {
	if p.regionCenter.X != 0 || p.regionCenter.Y != 0 {
		return p.regionCenter
	}

	if len(p.Points) == 0 {
		return Vec2{}
	}

	var cx, cy float64
	for _, pt := range p.Points {
		cx += pt.X
		cy += pt.Y
	}

	p.regionCenter = Vec2{
		X: cx / float64(len(p.Points)),
		Y: cy / float64(len(p.Points)),
	}

	return p.regionCenter
}

// computes and caches
func (p *Polygon) computeGeometry() {
	minX, minY, maxX, maxY := p.Bounds()
	p.bounds = [4]float64{minX, minY, maxX, maxY}
	p.area = p.Area()
	p.regionCenter = p.Center()
}

// ToPSLG converts to PSLG format for Triangle.c
func (p *Polygon) toPSLG(pointOffset int, boundaryMarkers map[string]int) ([]Vec2, []Segment, *Region) {
	segments := make([]Segment, len(p.Points))
	for i := 0; i < len(p.Points); i++ {
		marker := 0
		if p.Boundaries[i] != "" {
			marker = boundaryMarkers[p.Boundaries[i]]
		}
		segments[i] = Segment{
			P0:     pointOffset + i,
			P1:     pointOffset + (i+1)%len(p.Points),
			Marker: marker,
		}
	}

	region := &Region{
		Point:   p.regionCenter,
		ID:      p.RegionID,
		MaxArea: -1,
	}

	return p.Points, segments, region
}

//
// Helper constructors
//

func MakeRectangle(x, y, w, h float64, region string, boundaries ...string) Polygon {
	points := []Vec2{
		{x, y},
		{x + w, y},
		{x + w, y + h},
		{x, y + h},
	}

	var boundaryNames []string
	switch len(boundaries) {
	case 0:
		boundaryNames = []string{"", "", "", ""}
	case 1:
		b := boundaries[0]
		boundaryNames = []string{b, b, b, b}
	case 4:
		boundaryNames = boundaries
	default:
		panic("MakeRectangle: boundaries must be 0, 1, or 4 strings")
	}

	return Polygon{
		Points:     points,
		Region:     region,
		Boundaries: boundaryNames,
	}
}

func MakeCircle(cx, cy, radius float64, numSides int, region, boundary string) Polygon {
	if numSides < 3 {
		numSides = 32
	}

	points := make([]Vec2, numSides)
	boundaries := make([]string, numSides)

	for i := 0; i < numSides; i++ {
		angle := 2 * math.Pi * float64(i) / float64(numSides)
		points[i] = Vec2{
			X: cx + radius*math.Cos(angle),
			Y: cy + radius*math.Sin(angle),
		}
		boundaries[i] = boundary
	}

	return Polygon{
		Points:     points,
		Region:     region,
		Boundaries: boundaries,
	}
}

func MakePolygon(points []Vec2, region string, boundaries ...string) Polygon {
	var boundaryNames []string

	switch len(boundaries) {
	case 0:
		boundaryNames = make([]string, len(points))
	case 1:
		boundaryNames = make([]string, len(points))
		for i := range boundaryNames {
			boundaryNames[i] = boundaries[0]
		}
	default:
		if len(boundaries) != len(points) {
			panic("MakePolygon: boundaries length must match points length")
		}
		boundaryNames = boundaries
	}

	return Polygon{
		Points:     points,
		Region:     region,
		Boundaries: boundaryNames,
	}
}
