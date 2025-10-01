package fvm

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/profiler"
)

// SCENARIO RUNNING

var prof = profiler.NewProfiler()

func RunFrame(scenario Scenario, dt float32, tracerFieldIndex int) []float32 {
	scenario.advanceTime(dt)

	converged := false
	for !converged {
		converged = scenario.step(prof)
	}

	prof.PrintStatsEvery10Seconds(dt)

	return scenario.getTracerFieldValues()
}

// INTERFACES

type ScenarioDefinition interface {
	SetTracerField(name string) error
	Validate() error
	Resolve() (Scenario, error)
}

type Scenario interface {
	GetMesh() *geometry.Mesh
	step(prof profiler.Profiler) bool
	getTracerFieldValues() []float32
	advanceTime(dt float32)
}

// DEFINITIONS

// TODO: store fields and equations as raw structs - just accept them as
// interfaces in the factory function
type passiveTransportScenarioDefinition struct {
	mesh       geometry.MeshDefinition
	solver     linalg.SolverDefinition
	fields     []FieldDefinition
	equations  []EquationDefinition
	tracerName string
}

func NewPassiveTransportScenario(
	mesh geometry.MeshDefinition,
	solver linalg.SolverDefinition,
	fields []FieldDefinition,
	equations []EquationDefinition,
) ScenarioDefinition {
	return &passiveTransportScenarioDefinition{
		mesh:      mesh,
		solver:    solver,
		fields:    fields,
		equations: equations,
	}
}

func (pts *passiveTransportScenarioDefinition) SetTracerField(name string) error {
	for _, field := range pts.fields {
		if field, ok := field.(*scalarFieldDefinition); ok {
			if field.name == name {
				return nil
			}
		}
	}

	return fmt.Errorf("passiveTransportScenarioDefinition SetTracerField > Could not find field with name '%s'",
		name)
}

func (pts *passiveTransportScenarioDefinition) Validate() error {
	if len(pts.fields) == 0 {
		return fmt.Errorf("passiveTransportScenarioDefinition Validate > must have at least one field.")
	}

	// TODO: validate that the equations have the same boundary conditions (ie created with same mesh)
	// TODO: validate that all equation/operator coefficient fields are present

	for _, f := range pts.fields {
		if err := f.Validate(); err != nil {
			return err
		}
	}

	for _, eq := range pts.equations {
		if err := eq.Validate(); err != nil {
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

	fieldRegistry := make(map[string]field)
	scalarFields := make([]*scalarField, 0)
	vectorFields := make([]*vectorField, 0)

	for _, field := range pts.fields {
		res, err := field.resolve(mesh)
		if err != nil {
			return nil, fmt.Errorf("passiveScalarTransportScenarioDefinition resolve > %w",
				err)
		}

		switch field := res.(type) {
		case *scalarField:
			fieldRegistry[field.name] = field
			scalarFields = append(scalarFields, field)
		case *vectorField:
			fieldRegistry[field.name] = field
			vectorFields = append(vectorFields, field)
		default:
			return nil,
				fmt.Errorf("passiveScalarTransportScenarioDefinition resolve > could not cast field of type '%T'",
					field)
		}
	}

	scalarEquations := make([]*scalarEquation, 0)

	for _, eq := range pts.equations {
		res, err := eq.resolve(mesh, fieldRegistry)
		if err != nil {
			return nil,
				fmt.Errorf("passiveScalarTransportScenarioDefinition resolve > %w", err)
		}

		switch eq := res.(type) {
		case *scalarEquation:
			scalarEquations = append(scalarEquations, eq)
		default:
			return nil,
				fmt.Errorf("passiveScalarTransportScenarioDefinition resolve > could not cast equation of type '%T'",
					eq)
		}
	}

	tracerIndex := 0
	for i, field := range scalarFields {
		if field.name == pts.tracerName {
			tracerIndex = i
		}
	}

	return &passiveTransportScenario{
		mesh:   mesh,
		solver: pts.solver.Resolve(mesh.NumCells()),
		time:   0,

		scalarFields:    scalarFields,
		scalarEquations: scalarEquations,

		vectorFields: vectorFields,

		tracerIndex: tracerIndex,
	}, nil
}

// RESOLVED

type passiveTransportScenario struct {
	mesh   *geometry.Mesh
	solver linalg.Solver
	time   float32

	scalarFields    []*scalarField
	scalarEquations []*scalarEquation

	vectorFields []*vectorField

	tracerIndex int
}

func (pts *passiveTransportScenario) step(prof profiler.Profiler) bool {
	for _, eq := range pts.scalarEquations {
		endAssemblyTimer := prof.StartTimer("assembly")
		sys := eq.assembleSystem()
		endAssemblyTimer()

		endSolvingTimer := prof.StartTimer("solving")
		pts.solver.Solve(sys, eq.owner.cellValues)
		endSolvingTimer()
	}

	return true
}

func (pts *passiveTransportScenario) getTracerFieldValues() []float32 {
	field := pts.scalarFields[pts.tracerIndex]
	return field.cellValues
}

func (pts *passiveTransportScenario) GetMesh() *geometry.Mesh {
	return pts.mesh
}

func (pts *passiveTransportScenario) advanceTime(dt float32) {
	pts.time += dt

	for _, field := range pts.scalarFields {
		if field.fieldType == governed {
			governedScalarAdvanceTime(field)
		}
	}

	for _, field := range pts.vectorFields {
		if field.fieldType == derived {
			derivedVectorAdvanceTime(field, pts.time, pts.mesh.FaceNormals)
		}
	}

	for _, eq := range pts.scalarEquations {
		eq.advanceTime(dt)
		eq.runFluxOperators()
	}
}
