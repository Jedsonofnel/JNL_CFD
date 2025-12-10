package fvm

import (
	"errors"
	"math"
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
