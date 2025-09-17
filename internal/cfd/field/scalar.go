package field

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"math"
	"strings"
)

// DEFINITION

type ScalarFieldDefinition struct {
	Name         string
	InitialValue float32
	Mesh         geometry.MeshDefinition
	bcs          map[string]ScalarBC
	operators    []OperatorDefinition
	future       *scalar
}

func (sfd *ScalarFieldDefinition) GetName() string     { return sfd.Name }
func (sfd *ScalarFieldDefinition) getRank() TensorRank { return ScalarRank }
func (sfd *ScalarFieldDefinition) getType() FieldType  { return PrognosticType }

func (sfd *ScalarFieldDefinition) Validate() error {
	if sfd.Name == "" {
		return fmt.Errorf("Scalar Field Definition (%s) > Missing name", sfd.Name)
	}

	if len(sfd.bcs) == 0 {
		return fmt.Errorf("Scalar Field Definition (%s) > Missing boundary conditions", sfd.Name)
	}

	// if len(sfd.operators) == 0 {
	// 	return fmt.Errorf("Scalar Field Definition (%s) > Missing operators", sfd.Name)
	// }

	// err := validateOperatorsForField(sfd, sfd.operators)
	return nil
}

func (sfd *ScalarFieldDefinition) follow() Field {
	if sfd.future == nil {
		sfd.future = &scalar{}
	}

	return sfd.future
}

func (sfd *ScalarFieldDefinition) SetEquation(operators ...OperatorDefinition) error {
	if err := validateOperatorsForField(sfd, operators); err != nil {
		return fmt.Errorf("Set Equation (%s) > %w", err)
	}

	sfd.operators = operators
	return nil
}

func (sfd *ScalarFieldDefinition) SetBoundaryConditions(bcs map[string]ScalarBC) error {
	requiredBoundaries := make(map[string]bool)
	for _, name := range sfd.Mesh.GetBoundaries() {
		requiredBoundaries[name] = true
	}

	var missingBoundaries, unknownBoundaries []string

	for name := range bcs {
		if !requiredBoundaries[name] {
			unknownBoundaries = append(unknownBoundaries, name)
		} else {
			sfd.bcs[name] = bcs[name]
			delete(requiredBoundaries, name)
		}
	}

	for name := range requiredBoundaries {
		missingBoundaries = append(missingBoundaries, name)
	}

	var errParts []string
	if len(missingBoundaries) > 0 {
		errParts = append(errParts, fmt.Sprintf("Missing boundaries: %v", missingBoundaries))
	}
	if len(unknownBoundaries) > 0 {
		errParts = append(errParts, fmt.Sprintf("Unknown boundaries: %v", unknownBoundaries))
	}

	if len(errParts) > 0 {
		return fmt.Errorf("Scalar Field Definition (%s) > %s", sfd.Name, strings.Join(errParts, "; "))
	}
	return nil
}

func (sfd *ScalarFieldDefinition) Resolve(mesh *geometry.Mesh) (ScalarPrognostic, error) {
	if err := sfd.Validate(); err != nil {
		return nil, fmt.Errorf("Scalar Field (%s): Resolve > %w", sfd.Name, err)
	}

	sfd.future = &scalar{
		name: sfd.Name,
		mesh: mesh,
		bcs:  sfd.bcs,
		dt:   math.MaxFloat32,
	}

	sfd.future.cellValues = make([]float32, mesh.NumCells())
	sfd.future.cellValues0 = make([]float32, mesh.NumCells())

	for i := range sfd.future.cellValues {
		sfd.future.cellValues[i] = sfd.InitialValue
		sfd.future.cellValues0[i] = sfd.InitialValue
	}

	sfd.future.fluxOps = make([]ScalarFluxOperator, 0)
	sfd.future.srcOps = make([]ScalarSourceOperator, 0)

	for _, op := range sfd.operators {
		resOp, err := op.Resolve(sfd.future)
		if err != nil {
			return nil, fmt.Errorf("Scalar Field (%s): Resolve > %w", sfd.Name, err)
		}

		switch specificOp := resOp.(type) {
		case ScalarFluxOperator:
			sfd.future.fluxOps = append(sfd.future.fluxOps, specificOp)
		case ScalarSourceOperator:
			sfd.future.srcOps = append(sfd.future.srcOps, specificOp)
		default:
			return nil, fmt.Errorf("Scalar Field (%s): Resolve > Operator of type %T is neither a flux operator or source operator.",
				specificOp)
		}
	}

	sfd.future.sys = newSystemAssemblyContext(
		mesh.NumCells(), mesh.NumBoundaries(), mesh.NeighbourStarts, mesh.NeighbourIndices)

	return sfd.future, nil
}

// RESOLVED IMPLEMENTATION

type scalar struct {
	// Dependencies
	name string
	mesh *geometry.Mesh
	bcs  map[string]ScalarBC
	dt   float32

	// Data arrays
	cellValues  []float32
	cellValues0 []float32

	// Assembly
	fluxOps []ScalarFluxOperator
	srcOps  []ScalarSourceOperator

	// Linear system
	sys *systemAssemblyContext
}

func (s *scalar) AssembleSystem() *linalg.System {
	s.sys.PartialWipe() // internal matrix is set in AdvanceTime()
	s.sys.SyncDecoratedMatrix()

	// TODO: go through source operators and BCs and decorate
	// the actual matrix

	return &linalg.System{
		A: s.sys.Matrix, B: s.sys.RHS,
	}
}

// Public methods
func (s *scalar) GetName() string { return s.name }

func (s *scalar) GetValues() []float32 {
	return s.cellValues
}

func (s *scalar) SetValues(newValues []float32) {
	copy(s.cellValues, newValues)
}

func (s *scalar) AdvanceTime(dt float32) {
	s.dt = dt
	copy(s.cellValues0, s.cellValues)
	s.reassembleInternalMatrix()
}

func (s *scalar) SetTimestep(dt float32) {
	s.dt = dt
}

// Private methods
func (s *scalar) getRank() TensorRank     { return ScalarRank }
func (s *scalar) getType() FieldType      { return PrognosticType }
func (s *scalar) getMesh() *geometry.Mesh { return s.mesh }

func (s *scalar) getPastValues() []float32 {
	return s.cellValues0
}

func (s *scalar) getFaceValues() []float32 {
	// TODO: use distance weighted linear interpolation for this
	return make([]float32, 0)
}

func (s *scalar) getTimestep() float32 {
	return s.dt
}

func (s *scalar) reassembleInternalMatrix() {
	s.sys.FullWipe()

	// TODO: go through flux operators and apply fluxes
	for i, val := range s.cellValues {
		s.sys.MatrixInternal.SetDiagonal(i, 1)
		s.sys.RHS[i] = val
	}
}
