//go:build wasm

package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"syscall/js"
	"unsafe"
)

func main() {
	sm := geometry.NewStructuredMesh(5, 5, 10, 10)
	js.Global().Set("getMeshData", getMeshRenderData(sm))
	<-make(chan struct{})
}

func getMeshRenderData(md geometry.MeshDefinition) js.Func {
	var cb js.Func
	mesh := md.Resolve()
	mrd := geometry.NewMeshRenderData(mesh)

	// TODO: we want a MeshToWebGL function for this
	cb = js.FuncOf(func(this js.Value, args []js.Value) any {
		vertices := mrd.LineVertices
		jsFloat32Array := sliceToJSBuffer(vertices)

		cb.Release()

		return jsFloat32Array
	})

	return cb
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
