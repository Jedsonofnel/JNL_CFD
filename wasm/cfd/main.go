//go:build wasm

package main

import (
	"encoding/json"
	"unsafe"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	_ "github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"

	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

// STATE

var (
	globalCtx  *jnlisp.Context
	workingCtx *jnlisp.Context
	textBuf    []byte

	scenario fvm.Scenario
	rd       *fvm.RenderData
	mesh     *geometry.Mesh
)

func init() {
	textBuf = make([]byte, 1024*1024) // 1mB
	globalCtx = jnlisp.NewContext()

	globalCtx.ImportLibrary("cfd/fvm", "")
	globalCtx.ImportLibrary("cfd/geometry", "")
	globalCtx.ImportLibrary("cfd/linalg", "")

	workingCtx = globalCtx.Extend()
}

func main() {} // cursory but unused

//export getTextView
func getTextView() uint64 {
	ptr := uintptr(unsafe.Pointer(&textBuf[0]))
	length := int32(len(textBuf))
	return (uint64(ptr) << 32) | uint64(length)
}

//export evalText
func evalText(textLen int) uint64 {
	workingCtx = globalCtx.Extend()

	blocks := workingCtx.EvalBytes(textBuf[:textLen])
	jsonData, _ := json.Marshal(blocks)

	// PERF: consider whether GC might move the slice before consumption
	ptr := uintptr(unsafe.Pointer(&jsonData[0]))
	length := int32(len(jsonData))
	return (uint64(ptr) << 32) | uint64(length)
}

//export parseText
func parseText(textLen int) uint64 {
	blocks := jnlisp.ParseBytes(textBuf[:textLen])
	jsonBlock, _ := json.Marshal(blocks)

	ptr := uintptr(unsafe.Pointer(&jsonBlock[0]))
	length := int32(len(jsonBlock))
	return (uint64(ptr) << 32) | uint64(length)
}

// MESH RENDERING

//export loadMesh
func loadMesh(textLen int) int {
	meshDefSym := string(textBuf[:textLen])
	meshDefAtom, ok := workingCtx.GetBinding(meshDefSym)
	if !ok {
		println("COULD NOT FIND SYMBOL: " + meshDefSym)
		return 1
	}

	unwrappedAtom, ok := jnlisp.As[geometry.MeshDefinitionAtom](meshDefAtom)
	if !ok {
		println("COULD NOT CAST MESH TO ATOM")
		return 1
	}

	meshDef := unwrappedAtom.Value
	mesh = meshDef.Resolve()
	return 0
}

//export getMeshLineVertices
func getMeshLineVertices() uint64 {
	if mesh == nil {
		panic("CANNOT GET MESH VERTICES - MESH NOT LOADED")
	}

	mrd := geometry.NewMeshRenderData(mesh)

	ptr := uintptr(unsafe.Pointer(&mrd.LineVertices[0]))
	length := int32(len(mrd.LineVertices))
	return (uint64(ptr) << 32) | uint64(length)
}

//export getMeshTriVertices
func getMeshTriVertices() uint64 {
	if mesh == nil {
		panic("CANNOT GET MESH TRI VERTICES - MESH NOT LOADED")
	}

	mrd := geometry.NewMeshRenderData(mesh)

	ptr := uintptr(unsafe.Pointer(&mrd.TriangleVertices[0]))
	length := int32(len(mrd.TriangleVertices))
	return (uint64(ptr) << 32) | uint64(length)
}

//export getMeshAspectRatio
func getMeshAspectRatio() float64 {
	if mesh == nil {
		panic("CANNOT GET MESH METADATA - MESH NOT LOADED")
	}

	return float64(mesh.Bounds.Width / mesh.Bounds.Height)
}

// SCENARIO RENDERING

//export loadScenario
func loadScenario(textLen int) int {
	scenarioDefSym := string(textBuf[:textLen])
	scenarioDefAtom, ok := workingCtx.GetBinding(scenarioDefSym)
	if !ok {
		println("COULD NOT FIND SYMBOL: " + scenarioDefSym)
		return 1
	}

	unwrappedAtom, ok := jnlisp.As[fvm.ScenarioDefinitionAtom](scenarioDefAtom)

	scenarioDef := unwrappedAtom.Value
	newScenario, err := scenarioDef.Resolve()
	if err != nil {
		println("ERROR RESOLVING SCENARIO: " + err.Error())
		return 1
	}

	scenario = newScenario
	mesh = scenario.GetMesh()
	rd = fvm.NewRenderData(scenario)

	return 0
}

//export runFrame
func runFrame(dt float32) uint64 {
	if scenario == nil || rd == nil {
		panic("CANNOT RUN FRAME - SCENARIO NOT INITIALIZED")
	}

	results := fvm.RunFrame(scenario, dt, 0)
	normalisedResults := fvm.NormaliseResults(rd, results)

	ptr := uintptr(unsafe.Pointer(&normalisedResults[0]))
	length := int32(len(normalisedResults))
	return (uint64(ptr) << 32) | uint64(length)
}
