//go:build wasm

package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/field"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/simulation"
	"runtime"
	"syscall/js"
	"unsafe"
)

var allocCount uint64
var lastHeapSize uint64
var sharedResultsBuffer []float32

func main() {
	// state
	var mesh *geometry.Mesh

	var scenario *simulation.Scenario
	var rd **simulation.RenderData

	rd = new(*simulation.RenderData)
	scenario = new(simulation.Scenario)

	// mesh rendering
	js.Global().Set("getMeshData", getMeshRenderData(mesh))

	// scenario rendering
	js.Global().Set("setupScenarioViz", setupScenarioViz(scenario, rd))
	js.Global().Set("runFrame", runFrame(scenario, rd))

	// direct memory access functions
	js.Global().Set("getResultsPtr", getResultsPtr())
	js.Global().Set("getResultsLength", getResultsLength())

	<-make(chan struct{})
}

func getMeshRenderData(mesh *geometry.Mesh) js.Func {
	return js.FuncOf(func(_ js.Value, args []js.Value) any {
		nx, ny := args[0].Int(), args[1].Int()
		width, height := args[2].Float(), args[3].Float()

		sm := geometry.NewStructuredMesh(nx, ny, width, height)
		mesh = sm.Resolve()
		mrd := geometry.NewMeshRenderData(mesh)

		vertices := mrd.LineVertices
		jsFloat32Array := sliceToJSBuffer(vertices)

		return jsFloat32Array
	})
}

func setupScenarioViz(scenario *simulation.Scenario, rd **simulation.RenderData) js.Func {
	return js.FuncOf(func(_ js.Value, args []js.Value) any {
		if len(args) != 1 {
			panic("Require positional params: diffusivity")
		}
		diffusivity := args[0].Float()
		println(diffusivity)

		// setup code (manually for now until DSL)
		sm := geometry.NewStructuredMesh(200, 100, 1, 0.5)
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
		newScenario, err := sd.Resolve()
		if err != nil {
			panic(err)
		}
		*scenario = newScenario

		mesh := (*scenario).GetMesh()
		mrd := geometry.NewMeshRenderData(mesh)
		*rd = simulation.NewRenderData(mrd)

		// PRE-ALLOCATE the shared results buffer once
		resultSize := len((*rd).TriangleVertexColours)
		sharedResultsBuffer = make([]float32, resultSize)

		vertices := (*rd).TriangleVertices
		jsFloat32Array := sliceToJSBuffer(vertices)

		result := js.Global().Get("Object")
		result.Set("vertices", jsFloat32Array)
		result.Set("width", (*rd).Width)
		result.Set("height", (*rd).Height)

		return result
	})
}

func runFrame(scenario *simulation.Scenario, rd **simulation.RenderData) js.Func {
	return js.FuncOf(func(_ js.Value, args []js.Value) any {
		println("New run frame call")
		trackAllocs()
		if *scenario == nil || *rd == nil {
			panic("Cannot run frame without first calling setupScenarioViz()")
		}

		// dt := float32(args[0].Float())
		// fieldName := args[1].String()

		results := simulation.RunFrame(*scenario, 0.16, "temperature")

		println("Simulation contributions")
		trackAllocs()


		// normalisedResults := simulation.NormaliseResults(*rd, results)

		// copy(sharedResultsBuffer, results)

		for i := 0; i < len(results) && i < len(sharedResultsBuffer); i++ {
			sharedResultsBuffer[i] = results[i]
		}

		println("copying contributions")
		trackAllocs()

		return js.Null()
	})
}

// HELPERS

func trackAllocs() {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	if m.HeapAlloc != lastHeapSize {
		allocCount++
		println("Alloc #", allocCount, "Heap:", m.HeapAlloc, "Diff:", int64(m.HeapAlloc-lastHeapSize))
		lastHeapSize = m.HeapAlloc
	}
}

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

func getResultsPtr() js.Func {
	return js.FuncOf(func(_ js.Value, _ []js.Value) any {
		if len(sharedResultsBuffer) == 0 {
			return 0
		}
		ptr := uintptr(unsafe.Pointer(unsafe.SliceData(sharedResultsBuffer)))
		return ptr
	})
}

func getResultsLength() js.Func {
	return js.FuncOf(func(_ js.Value, _ []js.Value) any {
		return len(sharedResultsBuffer)
	})
}
