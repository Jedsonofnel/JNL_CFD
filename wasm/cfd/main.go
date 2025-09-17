//go:build wasm

package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/field"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/simulation"
	"syscall/js"
	"unsafe"
)

func main() {
	// state
	sm := geometry.NewStructuredMesh(5, 5, 10, 10)

	tf := &field.ScalarFieldDefinition{
		Name:         "temperature",
		InitialValue: 20.0,
		Mesh:         sm,
	}

	tf.SetBoundaryConditions(map[string]field.ScalarBC{
		"northBorder": nil,
		"eastBorder":  nil,
		"southBorder": nil,
		"westBorder":  nil,
	})

	solver := linalg.NewGaussSeidel(50, 1e-6)

	sd := simulation.NewPassiveTransportScenario(sm, solver, tf)
	scenario, err := sd.Resolve()
	if err != nil {
		panic(err)
	}

	mesh := scenario.GetMesh()
	mrd := geometry.NewMeshRenderData(mesh)
	rd := simulation.NewRenderData(mrd)

	// mesh rendering
	js.Global().Set("getMeshData", getMeshRenderData(mrd))

	// scenario rendering
	js.Global().Set("getFieldRenderGeometry", getFieldRenderGeometry(rd))
	js.Global().Set("runFrame", runFrame(scenario, rd))

	<-make(chan struct{})
}

func getMeshRenderData(mrd *geometry.MeshRenderData) js.Func {
	var cb js.Func

	cb = js.FuncOf(func(this js.Value, args []js.Value) any {
		vertices := mrd.LineVertices
		jsFloat32Array := sliceToJSBuffer(vertices)

		cb.Release()

		return jsFloat32Array
	})

	return cb
}

func getFieldRenderGeometry(rd *simulation.RenderData) (cb js.Func) {
	cb = js.FuncOf(func(this js.Value, args []js.Value) any {
		vertices := rd.TriangleVertices
		jsFloat32Array := sliceToJSBuffer(vertices)

		cb.Release()

		return jsFloat32Array
	})

	return
}

func runFrame(scenario simulation.Scenario, rd *simulation.RenderData) (cb js.Func) {
	cb = js.FuncOf(func(this js.Value, args []js.Value) any {
		dt := float32(args[0].Float())
		fieldName := args[1].String()

		results := simulation.RunFrame(scenario, dt, fieldName)
		normalisedResults := simulation.NormaliseResults(rd, results)

		jsResults := sliceToJSBuffer(normalisedResults)

		cb.Release()

		return jsResults
	})

	return
}

// HELPERS

func sliceToJSBuffer(slice []float32) js.Value {
	data := unsafe.Pointer(unsafe.SliceData(slice))
	length := len(slice) * 4

	bytes := unsafe.Slice((*byte)(data), length)

	jsUint8Array := js.Global().Get("Uint8Array").New(len(bytes))
	js.CopyBytesToJS(jsUint8Array, bytes)

	buffer := jsUint8Array.Get("buffer")
	jsFloat32Array := js.Global().Get("Float32Array").New(buffer)

	return jsFloat32Array
}
