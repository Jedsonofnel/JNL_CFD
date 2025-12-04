package geometry

import (
	_ "embed"

	jnl "jedn.dev/jnlisp"
)

var NS *jnl.Namespace

//go:embed geometry.jnl
var nsSrc string

//
// jnlisp geometry bindings
//

func init() {
	NS = jnl.NewNamespace("jnl.cfd.geometry", nsSrc)

	meshArity := jnl.PosArity("mesh")
	jnl.CreatePredicate[*Mesh](NS, "mesh")
	NS.BindNativeFn(".triangulate", jnl.PosArity("domain", "quality", "max-area"), triangulateMesh)
	NS.BindNativeFn(".mesh-ncells", meshArity, meshNumCells)
	NS.BindNativeFn(".mesh-nverts", meshArity, meshNumVertices)
	NS.BindNativeFn(".mesh-region-names", meshArity, meshRegionNames)
	NS.BindNativeFn(".mesh-boundary-names", meshArity, meshBoundaryNames)

	// DomainBuilder bindings
	jnl.CreatePredicate[*DomainBuilder](NS, "domain-builder")
	NS.BindNativeFn(".make-domain-builder", jnl.ZeroArity(), makeDomainBuilder)
	NS.BindNativeFn(".domain-builder-add-polygon", jnl.PosArity("builder", "polygon"), domainBuilderAddPolygon)
	NS.BindNativeFn(".domain-builder-add-hole", jnl.PosArity("builder", "polygon"), domainBuilderAddHole)
	NS.BindNativeFn(".domain-builder-build", jnl.PosArity("builder"), domainBuilderBuild)

	// Domain bindings
	jnl.CreatePredicate[*Domain](NS, "domain")
	NS.BindNativeFn(".domain-bounds", jnl.PosArity("domain"), domainBounds)

	// Polygon bindings
	jnl.CreatePredicate[*Polygon](NS, "polygon")
	NS.BindNativeFn(".make-rectangle", jnl.PosRestArity("x", "y", "w", "h", "region", "boundaries"), makeRectangle)
	NS.BindNativeFn(".make-circle", jnl.PosArity("cx", "cy", "radius", "num-sides", "region", "boundary"), makeCircle)
	NS.BindNativeFn(".make-polygon", jnl.PosRestArity("points", "region", "boundaries"), makePolygon)
	NS.BindNativeFn(".polygon-area", jnl.PosArity("polygon"), polygonArea)
	NS.BindNativeFn(".polygon-bounds", jnl.PosArity("polygon"), polygonBounds)
	NS.BindNativeFn(".polygon-contains", jnl.PosArity("polygon", "x", "y"), polygonContains)
}

// Domain builder Sexp implementation
func (db *DomainBuilder) String() string {
	return jnl.FormatNonReadable("cfd", "domain-builder")
}

func (db *DomainBuilder) Type() string {
	return "domain-builder"
}

func triangulateMesh(ctx *jnl.CallContext) (jnl.Sexp, error) {
	domain := jnl.GetArg[*Domain](ctx)
	quality := ctx.GetRationalArg()
	maxArea := ctx.GetRationalArg()
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	optString := buildTriangleOptions(quality, maxArea)
	mesh, err := MeshDomain(domain, optString)
	if err != nil {
		return nil, err
	}
	return mesh, nil
}

func meshNumCells(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*Mesh](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	nCells := len(mesh.Centroids)
	return jnl.Int(nCells), nil
}

func meshNumVertices(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*Mesh](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	nVerts := len(mesh.Vertices)
	return jnl.Int(nVerts), nil
}

func meshRegionNames(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*Mesh](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	mapp := jnl.NewMap()
	for i, name := range mesh.RegionNames {
		mapp.AssocBang(jnl.Int(i), jnl.String(name))
	}
	return mapp, nil
}

func meshBoundaryNames(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*Mesh](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	mapp := jnl.NewMap()
	for i, name := range mesh.BoundaryNames {
		mapp.AssocBang(jnl.Int(i), jnl.String(name))
	}
	return mapp, nil
}

func makeDomainBuilder(ctx *jnl.CallContext) (jnl.Sexp, error) {
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	return &DomainBuilder{}, nil
}

func domainBuilderAddPolygon(ctx *jnl.CallContext) (jnl.Sexp, error) {
	builder := jnl.GetArg[*DomainBuilder](ctx)
	polygon := jnl.GetArg[*Polygon](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	err := builder.AddPolygon(*polygon)
	if err != nil {
		return nil, err
	}
	return builder, nil
}

func domainBuilderAddHole(ctx *jnl.CallContext) (jnl.Sexp, error) {
	builder := jnl.GetArg[*DomainBuilder](ctx)
	polygon := jnl.GetArg[*Polygon](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	err := builder.AddHole(*polygon)
	if err != nil {
		return nil, err
	}
	return builder, nil
}

func domainBuilderBuild(ctx *jnl.CallContext) (jnl.Sexp, error) {
	builder := jnl.GetArg[*DomainBuilder](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	domain, err := builder.Build()
	if err != nil {
		return nil, err
	}
	return domain, nil
}

func domainBounds(ctx *jnl.CallContext) (jnl.Sexp, error) {
	domain := jnl.GetArg[*Domain](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	minX, minY, maxX, maxY := domain.Bounds()
	vec := jnl.NewVector()
	vec.AppendBang(jnl.Float(minX))
	vec.AppendBang(jnl.Float(minY))
	vec.AppendBang(jnl.Float(maxX))
	vec.AppendBang(jnl.Float(maxY))
	return vec, nil
}

func makeRectangle(ctx *jnl.CallContext) (jnl.Sexp, error) {
	x := jnl.GetArg[jnl.Float](ctx)
	y := jnl.GetArg[jnl.Float](ctx)
	w := jnl.GetArg[jnl.Float](ctx)
	h := jnl.GetArg[jnl.Float](ctx)
	region := jnl.GetArg[jnl.String](ctx)
	boundaries := jnl.GetVariadic[jnl.String](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	boundaryStrs := make([]string, len(boundaries))
	for i, b := range boundaries {
		boundaryStrs[i] = string(b)
	}

	poly := MakeRectangle(float64(x), float64(y), float64(w), float64(h), string(region), boundaryStrs...)
	return &poly, nil
}

func makeCircle(ctx *jnl.CallContext) (jnl.Sexp, error) {
	cx := jnl.GetArg[jnl.Float](ctx)
	cy := jnl.GetArg[jnl.Float](ctx)
	radius := jnl.GetArg[jnl.Float](ctx)
	numSides := jnl.GetArg[jnl.Int](ctx)
	region := jnl.GetArg[jnl.String](ctx)
	boundary := jnl.GetArg[jnl.String](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	poly := MakeCircle(float64(cx), float64(cy), float64(radius), int(numSides), string(region), string(boundary))
	return &poly, nil
}

func makePolygon(ctx *jnl.CallContext) (jnl.Sexp, error) {
	pointsVec := jnl.GetArg[jnl.Vector](ctx)
	region := jnl.GetArg[jnl.String](ctx)
	boundaries := jnl.GetVariadic[jnl.String](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	if pointsVec.Length()%2 != 0 {
		return nil, jnl.NewRuntimeError(
			jnl.ErrArgType,
			"points vector expected to be even length with [x y x y ...] pairs",
		).AtArg(1)
	}

	// Convert vector of [x y x y ...] to []Vec2
	points := make([]Vec2, pointsVec.Length()/2)
	for i := 0; i < pointsVec.Length()/2; i++ {
		x, _ := pointsVec.Nth(i * 2)
		y, _ := pointsVec.Nth(i*2 + 1)

		xRat := x.(jnl.Rational)
		yRat := y.(jnl.Rational)
		points[i] = Vec2{X: xRat.Rational(), Y: yRat.Rational()}
	}

	boundaryStrs := make([]string, len(boundaries))
	for i, b := range boundaries {
		boundaryStrs[i] = string(b)
	}

	poly := MakePolygon(points, string(region), boundaryStrs...)
	return &poly, nil
}

func polygonArea(ctx *jnl.CallContext) (jnl.Sexp, error) {
	polygon := jnl.GetArg[*Polygon](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	area := polygon.Area()
	return jnl.Float(area), nil
}

func polygonBounds(ctx *jnl.CallContext) (jnl.Sexp, error) {
	polygon := jnl.GetArg[*Polygon](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	minX, minY, maxX, maxY := polygon.Bounds()
	vec := jnl.NewVector()
	vec.AppendBang(jnl.Float(minX))
	vec.AppendBang(jnl.Float(minY))
	vec.AppendBang(jnl.Float(maxX))
	vec.AppendBang(jnl.Float(maxY))
	return vec, nil
}

func polygonContains(ctx *jnl.CallContext) (jnl.Sexp, error) {
	polygon := jnl.GetArg[*Polygon](ctx)
	x := jnl.GetArg[jnl.Float](ctx)
	y := jnl.GetArg[jnl.Float](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	contains := polygon.Contains(Vec2{X: float64(x), Y: float64(y)})
	return jnl.Bool(contains), nil
}
