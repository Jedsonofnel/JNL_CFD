//go:build wasm

package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/field"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/simulation"
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
var scenario simulation.Scenario
var rd *simulation.RenderData
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
	sm := geometry.NewStructuredMesh(200, 100, 1, 0.5)
	tf := field.NewScalarPrognosticDefinition("temperature", 20.0)

	tf.SetEquation(field.NewScalarLaplacian(tf, diffusivity))

	tf.SetBoundaryConditions(sm, map[string]field.ScalarBCDefinition{
		"northBorder": field.ScalarNeumann{},
		"eastBorder":  field.ScalarDirichlet{Value: 0.0},
		"southBorder": field.ScalarNeumann{},
		"westBorder":  field.ScalarDirichlet{Value: 20.0},
	})

	solver := linalg.NewGaussSeidel(10, 1e-6)
	sd := simulation.NewPassiveTransportScenario(sm, solver, tf)
	newScenario, err := sd.Resolve()
	if err != nil {
		panic(err)
	}
	scenario = newScenario

	mesh := scenario.GetMesh()
	mrd := geometry.NewMeshRenderData(mesh)
	rd = simulation.NewRenderData(mrd)

	// Update these in place
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

	results := simulation.RunFrame(scenario, dt, 0)

	normalisedResults := simulation.NormaliseResults(rd, results)
	ptr := uintptr(unsafe.Pointer(&normalisedResults[0]))
	length := int32(len(normalisedResults))

	return (uint64(ptr) << 32) | uint64(length)
}
