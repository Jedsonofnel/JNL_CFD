package geometry

import (
	"cmp"
	"errors"
	"slices"
)

//
// Domain builder that collects polygons and builds a domain
//

type DomainBuilder struct {
	polygons []Polygon
	err      error
}

func (db *DomainBuilder) AddPolygon(p Polygon) error {
	if db.err != nil {
		return nil
	}

	// Validate polygon
	if len(p.Points) < 3 {
		db.err = errors.New("polygon needs at least 3 points")
		return db.err
	}

	if len(p.Boundaries) != len(p.Points) {
		db.err = errors.New("boundaries length must match points length")
		return db.err
	}

	// Check for invalid intersections with existing polygons
	for i := range db.polygons {
		if p.Intersects(&db.polygons[i]) {
			db.err = errors.New("polygon intersects existing polygon")
			return db.err
		}
	}

	db.polygons = append(db.polygons, p)
	return nil
}

func (db *DomainBuilder) AddHole(p Polygon) error {
	if db.err != nil {
		return nil
	}

	// Reverse points to make it clockwise (hole convention)
	reversed := make([]Vec2, len(p.Points))
	for i := range p.Points {
		reversed[i] = p.Points[len(p.Points)-1-i]
	}
	p.Points = reversed

	// Also reverse boundaries to match
	reversedBoundaries := make([]string, len(p.Boundaries))
	for i := range p.Boundaries {
		reversedBoundaries[i] = p.Boundaries[len(p.Boundaries)-1-i]
	}
	p.Boundaries = reversedBoundaries

	p.IsHole = true

	return db.AddPolygon(p)
}

func (db *DomainBuilder) Build() (*Domain, error) {
	slices.SortFunc(db.polygons, func(p1, p2 Polygon) int {
		return cmp.Compare(p2.Area(), p1.Area())
	})

	domain := &Domain{
		Polygons:      db.polygons,
		layers:        make([]int, len(db.polygons)),
		parents:       make([]int, len(db.polygons)),
		regionNames:   make(map[string]int),
		boundaryNames: make(map[string]int),
		nextRegionID:  1,
		nextMarker:    1,
	}

	for i := range domain.Polygons {
		domain.Polygons[i].RegionID = domain.getOrCreateRegionID(domain.Polygons[i].Region)
		domain.Polygons[i].computeGeometry()
		for _, boundary := range domain.Polygons[i].Boundaries {
			if boundary != "" {
				domain.getOrCreateBoundaryMarker(boundary)
			}
		}
	}

	domain.computeLayers()

	return domain, nil
}

//
// Domain definition for meshing (internal mostly)
//

type Domain struct {
	Polygons      []Polygon
	layers        []int // layer index for each shape
	parents       []int // parent shape index (-1 if no parent)
	regionNames   map[string]int
	boundaryNames map[string]int
	nextRegionID  int
	nextMarker    int
}

func (d *Domain) getOrCreateRegionID(name string) int {
	if name == "" {
		name = "default"
	}
	if id, exists := d.regionNames[name]; exists {
		return id
	}
	id := d.nextRegionID
	d.regionNames[name] = id
	d.nextRegionID++
	return id
}

func (d *Domain) getOrCreateBoundaryMarker(name string) int {
	if name == "" {
		return 0 // Empty string = internal boundary, marker 0
	}
	if marker, exists := d.boundaryNames[name]; exists {
		return marker
	}
	marker := d.nextMarker
	d.boundaryNames[name] = marker
	d.nextMarker++
	return marker
}

// ComputeLayers calculates the containment hierarchy after all shapes are added
func (d *Domain) computeLayers() {
	n := len(d.Polygons)

	for i := range d.layers {
		d.layers[i] = 0
		d.parents[i] = -1
	}

	for i := 1; i < n; i++ {
		minX, minY, maxX, maxY := d.Polygons[i].Bounds()
		centerX := (minX + maxX) / 2
		centerY := (minY + maxY) / 2
		center := Vec2{centerX, centerY}

		// Find parent among earlier (larger) shapes
		parentIdx := -1
		for j := 0; j < i; j++ {
			if d.Polygons[j].Contains(center) {
				parentIdx = j
				break
			}
		}

		d.parents[i] = parentIdx

		// Start at parent's layer + 1
		baseLayer := 0
		if parentIdx >= 0 {
			baseLayer = d.layers[parentIdx] + 1
		}

		// Find the first available layer where we don't intersect with siblings
		layer := baseLayer
		for {
			hasConflict := false
			// Check all earlier polygons with the same parent at this layer
			for j := 0; j < i; j++ {
				if d.parents[j] == parentIdx && d.layers[j] == layer {
					if d.Polygons[i].Intersects(&d.Polygons[j]) {
						hasConflict = true
						break
					}
				}
			}
			if !hasConflict {
				break
			}
			layer++
		}

		d.layers[i] = layer
	}
}

func (d *Domain) GetLayer(idx int) int {
	if idx < 0 || idx >= len(d.layers) {
		return -1
	}
	return d.layers[idx]
}

func (d *Domain) Bounds() (minX, minY, maxX, maxY float64) {
	if len(d.Polygons) == 0 {
		return 0, 0, 1, 1
	}

	minX, minY, maxX, maxY = d.Polygons[0].Bounds()
	for _, poly := range d.Polygons[1:] {
		x0, y0, x1, y1 := poly.Bounds()
		minX = min(minX, x0)
		minY = min(minY, y0)
		maxX = max(maxX, x1)
		maxY = max(maxY, y1)
	}
	return
}

func (d *Domain) toPSLG() PSLG {
	var allPoints []Vec2
	var allSegments []Segment
	var allRegions []Region
	var allHoles []Vec2 // add this

	pointOffset := 0
	for i := range d.Polygons {
		poly := d.Polygons[i]
		pts, segs, reg := poly.toPSLG(pointOffset, d.boundaryNames)

		allPoints = append(allPoints, pts...)
		allSegments = append(allSegments, segs...)

		if poly.IsHole {
			allHoles = append(allHoles, poly.regionCenter)
		} else if reg != nil {
			allRegions = append(allRegions, *reg)
		}

		pointOffset += len(pts)
	}

	return PSLG{
		Points:   allPoints,
		Segments: allSegments,
		Regions:  allRegions,
		Holes:    allHoles,
	}
}
