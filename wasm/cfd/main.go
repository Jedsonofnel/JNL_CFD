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
	// TODO store up-to-date AST separately
	lispCtx *jnlisp.Context
	textBuf []byte

	scenario fvm.Scenario
	rd       *fvm.RenderData
	mesh     *geometry.Mesh
)

func init() {
	textBuf = make([]byte, 1024*1024) // 1mB
	lispCtx = jnlisp.NewContext()

	lispCtx.ImportLibrary("cfd/fvm", "")
	lispCtx.ImportLibrary("cfd/geometry", "")
	lispCtx.ImportLibrary("cfd/linalg", "")
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
	ctx := lispCtx.Extend()

	blocks := ctx.EvalBytes(textBuf[:textLen])
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

//export runFrame
func runFrame(dt float32) uint64 {
	if scenario == nil || rd == nil {
		return 0 // TODO: handle things not being initialised
	}

	results := fvm.RunFrame(scenario, dt, 0)

	normalisedResults := fvm.NormaliseResults(rd, results)

	ptr := uintptr(unsafe.Pointer(&normalisedResults[0]))
	length := int32(len(normalisedResults))

	return (uint64(ptr) << 32) | uint64(length)
}
