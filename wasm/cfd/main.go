//go:build wasm

package main

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"syscall/js"
	"unsafe"
)

func main() {
	sm := geometry.NewStructuredMesh(20, 20, 1, 1)
	js.Global().Set("getMeshData", getMeshRenderData(sm))
	<-make(chan struct{})
}

func getMeshRenderData(md geometry.MeshDefinition) js.Func {
	var cb js.Func
	mesh := md.Resolve()

	// TODO: we want a MeshToWebGL function for this
	cb = js.FuncOf(func(this js.Value, args []js.Value) any {
		vertices := mesh.CentroidsX // centroids for now

		if len(vertices) == 0 {
			return js.Global().Get("Float32Array").New(0)
		}

		data := unsafe.Pointer(unsafe.SliceData(vertices))
		length := len(vertices) * 4

		bytes := unsafe.Slice((*byte)(data), length)

		jsUint8Array := js.Global().Get("Uint8Array").New(len(bytes))
		js.CopyBytesToJS(jsUint8Array, bytes)

		buffer := jsUint8Array.Get("buffer")
		jsFloat32Array := js.Global().Get("Float32Array").New(buffer)

		cb.Release()

		return jsFloat32Array
	})

	return cb
}

// TODO: expose the right functions and not the wrong ones
// we are doing the webgl stuff in JAVASCRIPT while keeping the
// calculations in go for simplicity.  So actually we need to:
// 1. Get the mesh data correctly from the page -> may as well
//    spawn some sort of web worker and just resolve the mesh
//    immediately?
// 2. Send the resolved mesh data required for webgl rendering
//    back to javascript.
