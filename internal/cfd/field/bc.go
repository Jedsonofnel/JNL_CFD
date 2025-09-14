package field

import (
	"fmt"
)

type BCType int

const (
	DirichletType BCType = iota
	NeumannType
	OutflowType
)

type ScalarBCDefinition interface {
	Resolve(owner ScalarPrognostic, boundaryName string) ScalarBC
	GetType() BCType
}

type ScalarBC interface {
	ApplyFaceValues(faceValues []float32)
	// some sort of flux casting for neighbourwise
}

type ScalarDirichletDefinition struct{ Value float32 }

func (sdd ScalarDirichletDefinition) Resolve(owner ScalarPrognostic, boundaryName string) ScalarBC {
	mesh := owner.GetMesh()
	boundaryIndex := -1
	for i, name := range mesh.Boundaries {
		if name == boundaryName {
			boundaryIndex = i
		}
	}

	if boundaryIndex == -1 {
		panic(fmt.Sprintf("Could not find '%s' boundary on mesh for field '%s'",
			boundaryName, owner.GetName()))
	}

	connectivityIndices := make([]int, 0)
	for neighIdx := range mesh.CellNeighbours {
		if mesh.NeighbourTypes[neighIdx] == boundaryIndex {
			connectivityIndices = append(connectivityIndices, neighIdx)
		}
	}

	return &scalarDirichlet{
		connectivityIndices: connectivityIndices,
		value:               sdd.Value,
	}
}

type scalarDirichlet struct {
	connectivityIndices []int
	value               float32
}

func (sd scalarDirichlet) ApplyFaceValues(faceValues []float32) {
	for connIdx := range sd.connectivityIndices {
		faceValues[connIdx] = sd.value
	}
}

type ScalarNeumann struct{ Flux float32 }

func (sn ScalarNeumann) GetType() BCType   { return NeumannType }
func (sn ScalarNeumann) GetValue() float32 { return sn.Flux }

type ScalarOutflow struct{}

func (so ScalarOutflow) GetType() BCType   { return OutflowType }
func (so ScalarOutflow) GetValue() float32 { return 0.0 }

type VectorBC interface {
	GetType() BCType
	GetValue() [2]float32
}

type VectorDirichlet struct{ Value [2]float32 }

func (vd VectorDirichlet) GetType() BCType      { return DirichletType }
func (vd VectorDirichlet) GetValue() [2]float32 { return vd.Value }

type VectorNeumann struct{ Flux [2]float32 }

func (vn VectorNeumann) GetType() BCType      { return NeumannType }
func (vn VectorNeumann) GetValue() [2]float32 { return vn.Flux }

type VectorOutflow struct{}

func (vo VectorOutflow) GetType() BCType      { return OutflowType }
func (vo VectorOutflow) GetValue() [2]float32 { return [2]float32{0, 0} }
