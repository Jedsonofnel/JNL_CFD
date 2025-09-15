//go:build !wasm

package animation

import (
	"github.com/hajimehoshi/ebiten/v2"
)

func newPlatformAnimation(core *AnimationCore, nX, nY, width, height int, rd *geometry.RenderingData) Animation {
	nativeRenderer := renderer.NewNativeRenderer(nX, nY, width, height, rd)

	return &NativeAnimation{
		core:     core,
		renderer: nativeRenderer,
	}
}

type NativeAnimation struct {
	core     *AnimationCore
	renderer *renderer.NativeRenderer
}

func (na *NativeAnimation) Start() {
	ebiten.SetWindowSize(800, 400)
	ebiten.SetWindowTitle("CFD Simulation")
	ebiten.RunGame(na)
}

func (na *NativeAnimation) Update() error {
	na.core.Step(1.0 / 60.0)
	return nil
}

func (na *NativeAnimation) Draw(screen *ebiten.Image) {
	endRenderingTimer := na.core.profiler.StartTimer("rendering-step")
	tracerConcs := na.core.simulation.GetTracerConcentration()
	na.renderer.DrawToScreen(screen, tracerConcs)
	endRenderingTimer()
}

func (na *NativeAnimation) Layout(outsideWidth, outsideHeight int) (int, int) {
	return 800, 400
}
