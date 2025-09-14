//go:build wasm

package renderer

import (
	"fmt"
	"github.com/Jedsonofnel/cfd-but-wasm/simulation"
	"strconv"
	"syscall/js"
)

const (
	canvasID = "cfd-canvas"
)

type BrowserRenderer struct {
	core   *RendererCore
	canvas js.Value
	ctx    js.Value
}

func NewBrowserRenderer(nX, nY int) *BrowserRenderer {
	canvas := js.Global().Get("document").Call("getElementById", canvasID)
	width, height := getCanvasDimensions(canvas)
	ctx := canvas.Call("getContext", "2d")

	core := NewRendererCore(nX, nY, width, height)
	return &BrowserRenderer{core: core, canvas: canvas, ctx: ctx}
}

func (br *BrowserRenderer) DrawToCanvas(results *simulation.Results) {
	br.ctx.Set("fillStyle", "white")
	br.ctx.Call("fillRect", 0, 0, br.core.width, br.core.height)

	var vals []float32
	for _, fieldVals := range results.ScalarFields {
		vals = fieldVals
		break
	}

	br.core.ProcessField(vals)
	for _, cell := range br.core.cells {
		r, g, b, _ := cell.Color.RGBA()
		colorString := fmt.Sprintf("rgb(%d,%d,%d)", r, g, b)
		br.ctx.Set("fillStyle", colorString)
		br.ctx.Call("fillRect", cell.X, cell.Y, cell.Width+1, cell.Height+1)
	}
}

func getCanvasDimensions(c js.Value) (width, height int) {
	widthString := c.Call("getAttribute", "width").String()
	heightString := c.Call("getAttribute", "height").String()

	width, err := strconv.Atoi(widthString)
	if err != nil {
		panic("Canvas width attribute needs to be an integer")
	}

	height, err = strconv.Atoi(heightString)
	if err != nil {
		panic("Canvas height attribute needs to be an integer")
	}
	return width, height
}
