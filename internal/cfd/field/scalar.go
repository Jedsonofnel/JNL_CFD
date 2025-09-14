package field

import (
	"fmt"
	"github.com/Jedsonofnel/cfd-but-wasm/geometry"
	"github.com/Jedsonofnel/cfd-but-wasm/linalg"
	"strings"
)

// DEFINITION

type ScalarFieldDefinition struct {
	Name         string
	InitialValue float32
	Mesh         *geometry.Mesh
	bcs          map[string]ScalarBC
	operators    []OperatorDefinition
	future       *scalar
}

func (sfd *ScalarFieldDefinition) GetName() string     { return sfd.Name }
func (sfd *ScalarFieldDefinition) GetRank() TensorRank { return ScalarRank }
func (sfd *ScalarFieldDefinition) GetType() FieldType  { return PrognosticType }

func (sfd *ScalarFieldDefinition) Validate() error {
	if sfd.Name == "" {
		return fmt.Errorf("Scalar Field Definition (%s) > Missing name", sfd.Name)
	}

	if len(sfd.bcs) == 0 {
		return fmt.Errorf("Scalar Field Definition (%s) > Missing boundary conditions", sfd.Name)
	}

	if len(sfd.operators) == 0 {
		return fmt.Errorf("Scalar Field Definition (%s) > Missing operators", sfd.Name)
	}

	err := validateOperatorsForField(sfd, sfd.operators)
	return err
}

func (sfd *ScalarFieldDefinition) Follow() Field {
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
	for _, name := range sfd.Mesh.Boundaries {
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

func (sfd *ScalarFieldDefinition) Resolve() (ScalarPrognostic, error) {
	if err := sfd.Validate(); err != nil {
		return nil, fmt.Errorf("Scalar Field (%s): Resolve > %w", sfd.Name, err)
	}

	sfd.future = &scalar{
		name: sfd.Name,
		mesh: sfd.Mesh,
		bcs:  sfd.bcs,
		dt:   1.0,
	}

	sfd.future.cellValues = make([]float32, sfd.Mesh.NumCells())
	sfd.future.cellValues0 = make([]float32, sfd.Mesh.NumCells())

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

	sfd.future.fluxDiag = make([]float32, sfd.future.mesh.NumNeighbours())
	sfd.future.fluxOffDiag = make([]float32, sfd.future.mesh.NumNeighbours())
	sfd.future.sourceDiag = make([]float32, sfd.future.mesh.NumCells())

	sfd.future.matrix = linalg.NewCSRMatrixFromConnectivity(sfd.Mesh.NeighbourStarts, sfd.Mesh.CellNeighbours)
	sfd.future.rhs = make(linalg.Vector, sfd.Mesh.NumCells())

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
	fluxOps   []ScalarFluxOperator
	srcOps []ScalarSourceOperator

	// Linear system
	matrix linalg.Matrix
	rhs    linalg.Vector
}

func (s *scalar) AssembleSystem() *linalg.System {
	s.matrix.Wipe()
	s.rhs.Wipe()

	// Step 1 accumulate fluxes
	// Step 2 run boundary conditions on fluxes
	// Step 3 accumulate source diags + rhs
	// Step 4 loop through cells and neighbours and apply terms to matrix + rhs
	// Return

	for _, nwOp := range s.nwOps {
		// we want to cache these somehow diag, offDiag := nwOp.GetFluxes()

		for i := range s.cellValues {
			startIdx, endIdx := s.mesh.NeighbourStarts[i], s.mesh.NeighbourStarts[i+1]
			// use these to assemble row
		}
	}

	return &linalg.System{
		A: s.matrix, B: s.rhs,
	}
}

func (s *scalar) GetRank() TensorRank     { return ScalarRank }
func (s *scalar) GetName() string         { return s.name }
func (s *scalar) GetType() FieldType      { return PrognosticType }
func (s *scalar) GetMesh() *geometry.Mesh { return s.mesh }

func (s *scalar) GetValues() []float32 {
	return s.cellValues
}

func (s *scalar) SetValues(newValues []float32) {
	copy(s.cellValues, newValues)
}

func (s *scalar) GetFaceValues() []float32 {
	// TODO: use distance weighted linear interpolation for this
	return make([]float32, 0)
}

func (s *scalar) AdvanceTimeStep() {
	copy(s.cellValues0, s.cellValues)
}

func (s *scalar) GetTimestep() float32 {
	return s.dt
}

func (s *scalar) SetTimestep(dt float32) {
	s.dt = dt
}
