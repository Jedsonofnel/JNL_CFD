package simulation
// 
// import (
// 	"fmt"
// )
// 
// type UniformVelocity struct {
// 	mesh          *geometry.Mesh
// 	velocityField *field.UniformVelocity
// 	cpd           []float32
// 	tracerField   *field.Scalar
// 	solver        linalg.Solver
// 	time          float32
// 	profiler      profiler.Profiler
// }
// 
// func NewUniformVelocitySimulation(mesh *geometry.Mesh, profiler profiler.Profiler) Simulation {
// 	solver := linalg.NewGaussSeidel(numIterations, tolerance)
// 	velocityField := field.NewUniformVelocityField(mesh, velocityTimeDepX, velocityTimeDepY)
// 
// 	dyeTracerConfig := field.ScalarConfig{
// 		Diffusivity:  1e-4,
// 		StorageCoeff: 1.0,
// 		InitialValue: 0,
// 	}
// 
// 	tracerField := field.NewScalarField(mesh, dyeTracerConfig)
// 	tracerField.ApplyBoundaryConditions(map[string]field.ScalarBC{
// 		"north": field.ScalarNeumann{Flux: 0.0},
// 		"east":  field.ScalarOutflow{},
// 		"south": field.ScalarNeumann{Flux: 0.0},
// 		"west":  field.ScalarDirichlet{Value: 1.0},
// 	})
// 	tracerField.Resolve()
// 
// 	return &UniformVelocity{
// 		mesh:          mesh,
// 		velocityField: velocityField,
// 		cpd:           make([]float32, mesh.NumCells()),
// 		tracerField:   tracerField,
// 		solver:        solver,
// 		time:          0.5,
// 		profiler:      profiler,
// 	}
// }
// 
// func (uv *UniformVelocity) Step(dt float32) {
// 	if dt <= 0.001 {
// 		// Granted I'm using an implicit time discretisation so this is nonsense
// 		panic(fmt.Sprintf("Cannot have a dt as small as %.6f for stability reasons", dt))
// 	}
// 
// 	defer uv.profiler.StartTimer("simulation-step")()
// 
// 	// step 1 update uniform velocity field
// 	endVelocityTimer := uv.profiler.StartTimer("velocity-update")
// 	uv.velocityField.UpdateValues(uv.time)
// 	cvd := uv.velocityField.GetCellVelocityData()
// 	endVelocityTimer()
// 
// 	// step 2 assemble tracer field
// 	endAssemblyTimer := uv.profiler.StartTimer("assembly")
// 	system := uv.tracerField.AssembleSystem(dt, uv.cpd, cvd)
// 	endAssemblyTimer()
// 
// 	// step 3 solve tracer field
// 	endSolvingTimer := uv.profiler.StartTimer("solving")
// 	solution := uv.solver.Solve(system)
// 	endSolvingTimer()
// 
// 	// step 4 update tracer field
// 	endUpdatingTimer := uv.profiler.StartTimer("updating")
// 	uv.tracerField.UpdateValues(solution)
// 	uv.tracerField.AdvanceTimeStep()
// 	endUpdatingTimer()
// 
// 	// step 5 update simulation time
// 	uv.time += dt
// }
// 
// func (uv *UniformVelocity) GetTracerConcentration() []float32 {
// 	return uv.tracerField.GetValues()
// }
// 
// func velocityTimeDepX(t float32) float32 {
// 	return 0.0001
// }
// 
// func velocityTimeDepY(t float32) float32 {
// 	return 0.001
// }
