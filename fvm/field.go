package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/geometry"
)

//
// Fields corresponding to physical quantities
//

type Field struct {
	name   string
	Values []float64
	Scalar float64
}

func (f *Field) IsScalar() bool {
	return f.Values == nil
}

func (f *Field) Get(i int) float64 {
	if f.Values == nil {
		return f.Scalar
	}
	return f.Values[i]
}

//
// Context is the mathematical namespace
//

type Context struct {
	Mesh   *geometry.Mesh
	Fields map[string]*Field

	Regions map[int]string
}

func NewContext(mesh *geometry.Mesh) *Context {
	return &Context{
		Mesh:    mesh,
		Fields:  make(map[string]*Field),
		Regions: mesh.RegionNames,
	}
}

func (ctx *Context) AddField(name string, values []float64) {
	if _, exists := ctx.Fields[name]; exists {
		panic("context already contains field with name " + name)
	}

	if name == "" {
		panic("context cannot create a field with an empty name")
	}

	nVals := len(ctx.Mesh.Centroids)
	if len(values) != nVals {
		panic("context cannot create a field with a different number of values as cells")
	}

	ctx.Fields[name] = &Field{
		name:   name,
		Values: values,
	}
}

func (ctx *Context) AddUniformField(name string, value float64) {
	nCells := len(ctx.Mesh.Centroids)
	values := make([]float64, nCells)
	for i := range values {
		values[i] = value
	}
	ctx.AddField(name, values)
}

func (ctx *Context) AddConstantField(name string, value float64) {
	if _, exists := ctx.Fields[name]; exists {
		panic("context already contains field with name " + name)
	}

	if name == "" {
		panic("context cannot create a field with an empty name")
	}

	ctx.Fields[name] = &Field{
		name:   name,
		Values: nil,
		Scalar: value,
	}
}

// AddRegionField adds a field with region-specific values
// regionValues maps region name -> value
// defaultValue is used for regions not in the map
func (ctx *Context) AddRegionField(name string, regionValues map[string]float64, defaultValue float64) {
	nCells := len(ctx.Mesh.Centroids)
	values := make([]float64, nCells)

	for i, regionIdx := range ctx.Mesh.CellRegions {
		regionName := ctx.Regions[regionIdx]

		if val, ok := regionValues[regionName]; ok {
			values[i] = val
		} else {
			values[i] = defaultValue
		}
	}

	ctx.AddField(name, values)
}

// SetRegionValues modifies a field's values for specific regions
func (ctx *Context) SetRegionValues(fieldName, regionName string, value float64) {
	field, ok := ctx.Fields[fieldName]
	if !ok {
		panic("field " + fieldName + " not found")
	}
	if field.IsScalar() {
		panic("cannot set region values on constant field " + fieldName)
	}

	for i, regionIdx := range ctx.Mesh.CellRegions {
		if ctx.Regions[regionIdx] == regionName {
			field.Values[i] = value
		}
	}
}
