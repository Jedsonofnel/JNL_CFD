package simulation

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/field"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

type Scenario interface {
	Step() bool
	GetScalarFieldValues(name string) []float32
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

	prognosticScalarFields map[string]field.ScalarPrognostic
	// timeEvolvingDiagnosticFields []field.TimeEvolving
	// constant fields? []field.Field
}

func (pts *passiveTransportScenario) Step() bool {
	for _, f := range pts.prognosticScalarFields {
		_ = f.AssembleSystem()
		// solutions := pts.solver.Solve(sys)
		// f.SetValues(solutions)
	}

	return true
}

func (pts *passiveTransportScenario) GetScalarFieldValues(name string) []float32 {
	field := pts.prognosticScalarFields[name]
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
	mesh   geometry.MeshDefinition
	solver linalg.Solver
	fields []field.FieldDefinition
}

func NewPassiveTransportScenario(
	mesh geometry.MeshDefinition,
	solver linalg.Solver,
	fields ...field.FieldDefinition,
) ScenarioDefinition {
	return &passiveTransportScenarioDefinition{
		mesh:   mesh,
		solver: solver,
		fields: fields,
	}
}

func (pts *passiveTransportScenarioDefinition) Validate() error {
	// what does validation look like??
	// TODO: validate that the fields have the same mesh
	// TODO: validate that all coupled fields are present

	for _, f := range pts.fields {
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
	fields := make(map[string]field.ScalarPrognostic, 0)

	for _, f := range pts.fields {
		switch field := f.(type) {
		case field.ScalarPrognosticDefinition:
			res, err := field.ResolveAsPrognostic(mesh)

			if err != nil {
				return nil, err
			}

			fields[res.GetName()] = res
		default:
			return nil, fmt.Errorf("passiveTransportScenarioDefinition > Resolve (%s) > Field type %T not implemented.",
				field.GetName(), field)
		}
	}

	return &passiveTransportScenario{
		mesh:   mesh,
		solver: pts.solver,

		prognosticScalarFields: fields,
	}, nil
}
