//go:build wasm

package animation

import (
	"syscall/js"
)

func newPlatformAnimation(core *AnimationCore, nX, nY, width, height int) Animation {
	browserRenderer := renderer.NewBrowserRenderer(nX, nY)

	return &BrowserAnimation{
		core:     core,
		renderer: browserRenderer,
	}
}

type BrowserAnimation struct {
	core     *AnimationCore
	renderer *renderer.BrowserRenderer
}

func (ba *BrowserAnimation) Start() {
	var animationFrame js.Func
	var lastTime float32
	firstFrame := true

	animationFrame = js.FuncOf(func(this js.Value, args []js.Value) any {
		currentTime := float32(args[0].Float())
		var dt float32

		if firstFrame {
			dt = 0.016
			firstFrame = false
		} else {
			dt = (currentTime - lastTime) / 1000.0 // Convert to s from ms
		}
		
		// Throttling for stability
		if dt > 0.016 { // Min 30 FPS
			dt = 0.033
		} else if dt < 0.001 { // Max 1000 FPS
			dt = 0.001
		}

		lastTime = currentTime
		ba.Step(dt)

		js.Global().Call("requestAnimationFrame", animationFrame)
		return nil
	})

	js.Global().Call("requestAnimationFrame", animationFrame)
}

func (ba *BrowserAnimation) Step(dt float32) {
	ba.core.Step(dt)

	endRenderingTimer := ba.core.profiler.StartTimer("rendering-step")
	ba.renderer.DrawToCanvas(ba.core.results)
	endRenderingTimer()
}
