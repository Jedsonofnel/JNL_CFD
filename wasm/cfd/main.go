//go:build wasm

package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"unsafe"
)

func main() {} // cursory but unused

// memory sharing
var shared struct {
	NX     int32
	NY     int32
	Width  float32
	Height float32
}

//export getSharedMemLoc
func getSharedMemLoc() uint64 {
	ptr := uintptr(unsafe.Pointer(&shared))
	length := int32(unsafe.Sizeof(shared))
	return (uint64(ptr) << 32) | uint64(length)
}

// state
var scenario fvm.Scenario
var rd *fvm.RenderData
var mesh *geometry.Mesh

//export getMeshRenderData
func getMeshRenderData() uint64 {
	sm := geometry.NewStructuredMesh(
		int(shared.NX), int(shared.NY), float64(shared.Width), float64(shared.Height),
	)

	mesh = sm.Resolve()
	mrd := geometry.NewMeshRenderData(mesh)

	vertices := mrd.LineVertices

	ptr := uintptr(unsafe.Pointer(&vertices[0]))
	length := int32(len(vertices))

	return (uint64(ptr) << 32) | uint64(length)
}

//export setupScenarioViz
func setupScenarioViz(diffusivity float32) uint64 {
	// setup code (manually for now until DSL)
	sm := geometry.NewStructuredMesh(50, 25, 1, 0.6)
	tf := fvm.NewPrognosticScalarField("temperature", 20.0)

	eq, err := fvm.NewEquation(tf,
		fvm.NewLaplacian(tf, diffusivity),
	)
	if err != nil {
		panic(err)
	}

	eq.SetBoundaryConditions(sm, map[string]fvm.BCDefinition{
		"northBorder": fvm.ScalarNeumann{},
		"eastBorder":  fvm.ScalarDirichlet{Value: 5.0},
		"southBorder": fvm.ScalarNeumann{},
		"westBorder":  fvm.ScalarDirichlet{Value: 20.0},
	})

	solver := linalg.NewJacobiCG(50, 1e-2)
	sd := fvm.NewPassiveTransportScenario(sm, solver,
		[]fvm.FieldDefinition{tf}, []fvm.EquationDefinition{eq})

	newScenario, err := sd.Resolve()
	if err != nil {
		panic(err)
	}
	scenario = newScenario

	rd = fvm.NewRenderData(scenario)

	// Update these in place
	shared.NX = 50
	shared.NY = 20
	shared.Width = rd.Width
	shared.Height = rd.Height

	vertices := rd.TriangleVertices
	ptr := uintptr(unsafe.Pointer(&vertices[0]))
	length := int32(len(vertices))

	return (uint64(ptr) << 32) | uint64(length)
}

//export runFrame
func runFrame(dt float32) uint64 {
	if scenario == nil || rd == nil {
		panic("Cannot run frame without first calling setupScenarioViz()")
	}

	results := fvm.RunFrame(scenario, dt, 0)

	normalisedResults := fvm.NormaliseResults(rd, results)

	ptr := uintptr(unsafe.Pointer(&normalisedResults[0]))
	length := int32(len(normalisedResults))

	return (uint64(ptr) << 32) | uint64(length)
}
