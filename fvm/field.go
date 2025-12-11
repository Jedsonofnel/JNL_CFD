package fvm

import (
	"errors"
	"math"

	"github.com/Jedsonofnel/jnlcfd/geometry"
	jnl "jedn.dev/jnlisp"
)

//
// FVM/field.go
//

func UpdateTriField(triField, results []float64, triToCells []int) error {
	if len(triField) != len(triToCells)*3 {
		return errors.New("triField does not have the right length")
	}

	maxResult, minResult := -math.MaxFloat64, math.MaxFloat64

	for i := range results {
		maxResult = max(maxResult, results[i])
		minResult = min(minResult, results[i])
	}

	resultRange := maxResult - minResult

	for triIdx, cellIdx := range triToCells {
		res := results[cellIdx]
		normalised := (res - minResult) / resultRange
		triField[triIdx+0] = normalised
		triField[triIdx+1] = normalised
		triField[triIdx+2] = normalised
	}

	return nil
}

//
// Context (lisp map) helpers
//

func GetMesh(ctx jnl.Map) (*geometry.Mesh, error) {
	meshVal := ctx.Lookup(jnl.NewKeyword("mesh"))
	if meshVal == (jnl.Nil{}) || meshVal == nil {
		return nil, errors.New(":mesh not found in context")
	}
	mesh, ok := meshVal.(*geometry.Mesh)
	if !ok {
		return nil, errors.New(":mesh is not a Mesh")
	}
	return mesh, nil
}

// GetValues extracts :values map from context
func GetValues(ctx jnl.Map) (jnl.Map, error) {
	valuesVal := ctx.Lookup(jnl.NewKeyword("values"))
	if valuesVal == (jnl.Nil{}) || valuesVal == nil {
		return jnl.Map{}, errors.New(":values not found in context")
	}
	values, ok := valuesVal.(jnl.Map)
	if !ok {
		return jnl.Map{}, errors.New(":values is not a map")
	}
	return values, nil
}

// GetExpression extracts field from :values and returns Expression
func GetFieldExpression(ctx jnl.Map, key string) (*Expression, error) {
	values, err := GetValues(ctx)
	if err != nil {
		return nil, err
	}

	val := values.Lookup(jnl.NewKeyword(key))
	if val == (jnl.Nil{}) || val == nil {
		return nil, errors.New("field '" + key + "' not found in :values")
	}

	switch v := val.(type) {
	case jnl.Float:
		return ConstExpr(float64(v)), nil
	case jnl.Int:
		return ConstExpr(float64(v)), nil
	case jnl.FloatTuple:
		values := v.Elements
		return &Expression{
			Eval: func(i int) float64 { return values[i] },
		}, nil
	default:
		return nil, errors.New("cannot convert " + v.Type() + " to expression (key: " + key + ")")
	}
}
