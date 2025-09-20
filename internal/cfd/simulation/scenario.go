package simulation

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/field"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/profiler"
)

type Scenario interface {
	Step(prof profiler.Profiler) bool
	GetScalarPrognosticValues(index int) []float32
	AdvanceTime(dt float32)
	GetMesh() *geometry.Mesh
}

type ScenarioDefinition interface {
	Validate() error
	Resolve() (Scenario, error)
}

// IMPLEMENTATIONS

type passiveTransportScenario struct {
	mesh   *geometry.Mesh
	solver linalg.Solver

	prognosticScalarFields []*field.ScalarPrognostic
	// timeEvolvingDiagnosticFields []field.TimeEvolving
	// constant fields? []field.Field
}

func (pts *passiveTransportScenario) Step(prof profiler.Profiler) bool {
	for _, f := range pts.prognosticScalarFields {
		endAssemblyTimer := prof.StartTimer("assembly")
		sys := f.AssembleSystem()
		endAssemblyTimer()

		endSolvingTimer := prof.StartTimer("solving")
		pts.solver.Solve(sys, f.GetValues())
		endSolvingTimer()
	}

	return true
}

func (pts *passiveTransportScenario) GetScalarPrognosticValues(index int) []float32 {
	field := pts.prognosticScalarFields[index]
	return field.GetValues()
}

func (pts *passiveTransportScenario) AdvanceTime(dt float32) {
	for _, f := range pts.prognosticScalarFields {
		f.AdvanceTime(dt)
	}
}

func (pts *passiveTransportScenario) GetMesh() *geometry.Mesh {
	return pts.mesh
}

type passiveTransportScenarioDefinition struct {
	mesh        geometry.MeshDefinition
	solver      linalg.SolverDefinition
	scalarProgs []*field.ScalarPrognosticDefinition
}

func NewPassiveTransportScenario(
	mesh geometry.MeshDefinition,
	solver linalg.SolverDefinition,
	fields ...any,
) ScenarioDefinition {
	scalarProgs := make([]*field.ScalarPrognosticDefinition, 0)

	for _, f := range fields {
		switch field := f.(type) {
		case *field.ScalarPrognosticDefinition:
			scalarProgs = append(scalarProgs, field)
		default:
			panic("Passed something unknown to NewPassiveTransporScenario")
		}
	}

	return &passiveTransportScenarioDefinition{
		mesh:        mesh,
		solver:      solver,
		scalarProgs: scalarProgs,
	}
}

func (pts *passiveTransportScenarioDefinition) Validate() error {
	// what does validation look like??
	// TODO: validate that the fields have the same mesh
	// TODO: validate that all coupled fields are present

	for _, f := range pts.scalarProgs {
		if err := f.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (pts *passiveTransportScenarioDefinition) Resolve() (Scenario, error) {
	if err := pts.Validate(); err != nil {
		return nil, err
	}

	mesh := pts.mesh.Resolve()

	fields := make([]*field.ScalarPrognostic, 0)

	for _, field := range pts.scalarProgs {
		res, err := field.Resolve(mesh)

		if err != nil {
			return nil, err
		}

		fields = append(fields, res)
	}

	return &passiveTransportScenario{
		mesh:   mesh,
		solver: pts.solver.Resolve(mesh.NumCells()),

		prognosticScalarFields: fields,
	}, nil
}
