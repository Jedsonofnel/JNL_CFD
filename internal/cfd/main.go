package main

import (
	"github.com/Jedsonofnel/cfd-but-wasm/animation"
	"github.com/Jedsonofnel/cfd-but-wasm/geometry"
	"github.com/Jedsonofnel/cfd-but-wasm/profiler"
	"github.com/Jedsonofnel/cfd-but-wasm/simulation"
)

func main() {
	done := make(chan struct{})
	prof := profiler.NewProfiler()

	// we want mesh
	nX, nY := 21, 11
	var width, height float32 = 0.01, 0.05
	mesh := geometry.NewStructuredMesh(nX, nY, width, height)

	// we want to define velocity

	// we want to define pressure

	// we want to define tracer here

	// we want to apply boundary conditions

	// we want to specify a scheme

	// we want to pass these all to a real time animation case
	sim := simulation.NewUniformVelocitySimulation(mesh, prof)

	anim := animation.NewAnimation(sim, prof, nX, nY, mesh.RenderingData())
	anim.Start()
	<-done
}
