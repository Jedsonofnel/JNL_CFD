package animation

import (
	"time"
)

type Animation interface {
	Start()
}

type AnimationCore struct {
	simulation      simulation.Simulation
	profiler        profiler.Profiler
	lastProfileTime time.Time
}

func NewAnimationCore(
	sim simulation.Simulation,
	prof profiler.Profiler,
) *AnimationCore {
	now := time.Now()

	return &AnimationCore{
		simulation:      sim,
		profiler:        prof,
		lastProfileTime: now,
	}
}

func (ac *AnimationCore) Step(dt float32) {
	ac.simulation.Step(dt)

	if time.Since(ac.lastProfileTime) >= 10*time.Second {
		ac.profiler.PrintStats()
		ac.profiler.Reset()
		ac.lastProfileTime = time.Now()
	}
}

func NewAnimation(
	sim simulation.Simulation,
	prof profiler.Profiler,
	nX, nY int,
	rd *geometry.RenderingData,
) Animation {
	core := NewAnimationCore(sim, prof)
	return newPlatformAnimation(core, nX, nY, 800, 400, rd)
}
