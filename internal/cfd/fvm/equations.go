package fvm

import (
	"fmt"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"math"
	"strings"
)

// INTERFACES

type EquationDefinition interface {
	Validate() error
	SetBoundaryConditions(md geometry.MeshDefinition, bcs map[string]BCDefinition) error
	resolve(mesh *geometry.Mesh, fields map[string]field) (equation, error)
	rank() rank
}

type equation interface {
	rank() rank
}

// DEFINITIONS

type scalarEquationDefinition struct {
	owner     *scalarFieldDefinition
	bcs       map[string]BCDefinition
	operators []OperatorDefinition
}

func newScalarEquationDefinition(owner *scalarFieldDefinition,
	operators ...OperatorDefinition) (*scalarEquationDefinition, error) {

	for _, op := range operators {
		if op.rank() != scalar {
			return nil, fmt.Errorf("newScalarEquationDefinition (%s) > Cannot include operator with rank %d.",
				owner.name, op.rank())
		}

		if err := op.Validate(); err != nil {
			return nil, fmt.Errorf("newScalarEquationDefinition (%s) > Invalid operator: %w",
				owner.name, err)
		}
	}

	return &scalarEquationDefinition{
		owner:     owner,
		bcs:       make(map[string]BCDefinition),
		operators: operators,
	}, nil
}

func (sed *scalarEquationDefinition) Validate() error {
	return nil
}

func (sed *scalarEquationDefinition) SetBoundaryConditions(
	md geometry.MeshDefinition, bcs map[string]BCDefinition) error {
	requiredBoundaries := make(map[string]bool)
	for _, name := range md.GetBoundaries() {
		requiredBoundaries[name] = true
	}

	var missingBoundaries, unknownBoundaries []string

	for name, bc := range bcs {
		if bc.rank() != scalar {
			return fmt.Errorf("scalarEquationDefinition (%s) SetBoundaryConditions > cannot use boundary of rank %d",
				sed.owner.name, bc.rank())
		}
		if !requiredBoundaries[name] {
			unknownBoundaries = append(unknownBoundaries, name)
		} else {
			sed.bcs[name] = bc
			delete(requiredBoundaries, name)
		}
	}

	for name := range requiredBoundaries {
		missingBoundaries = append(missingBoundaries, name)
	}

	var errParts []string
	if len(missingBoundaries) > 0 {
		errParts = append(errParts, fmt.Sprintf("Missing boundaries: %v",
			missingBoundaries))
	}
	if len(unknownBoundaries) > 0 {
		errParts = append(errParts, fmt.Sprintf("Unknown boundaries: %v",
			unknownBoundaries))
	}

	if len(errParts) > 0 {
		return fmt.Errorf("ScalarPrognosticDefinition (%s) > %s",
			sed.owner.name, strings.Join(errParts, ";"))
	}

	return nil
}

func (sed *scalarEquationDefinition) resolve(mesh *geometry.Mesh,
	fields map[string]field) (equation, error) {
	resolved, found := fields[sed.owner.name]
	if !found {
		return nil, fmt.Errorf("scalarEquationDefinition (%s) resolve > could not find field in registry.",
			sed.owner.name)
	}

	owner, ok := resolved.(*scalarField)
	if !ok {
		return nil, fmt.Errorf("scalarEquationDefinition (%s) resolve > could not cast to *scalarField.",
			sed.owner.name)
	}

	// TODO: assert that the mesh is the same as the one ascribed in SetBoundaryConditions
	bcs := make([]*scalarBC, len(sed.bcs))
	for i, name := range mesh.Boundaries {
		// TODO maybe check that it's found
		bc := sed.bcs[name].resolve(mesh, name)
		cast, ok := bc.(*scalarBC)
		if !ok {
			return nil,
				fmt.Errorf("scalarEquationDefinition (%s) resolve > could not cast boundary for '%s' with type '%T'",
					name, cast)
		}
		bcs[i] = cast
	}

	// resolving the operator definitions
	sourceOps := make([]*scalarOperator, 0)
	fluxOps := make([]*scalarOperator, 0)
	for _, opDef := range sed.operators {
		resolved, err := opDef.resolve(mesh, fields)
		if err != nil {
			return nil,
				fmt.Errorf("scalarEquationDefinition (%s) resolve > %w", sed.owner.name, err)
		}

		op, ok := resolved.(*scalarOperator)
		if !ok {
			return nil,
				fmt.Errorf("scalarEquationDefinition (%s) resolve > coud not cast operator with type '%T' to *scalarOperator",
					sed.owner.name, resolved)
		}

		if op.opType > 1 { // ie laplacian and div are 0 and 1 respectively
			sourceOps = append(sourceOps, op)
		} else {
			fluxOps = append(fluxOps, op)
		}
	}

	// setting up linalg data structures
	matrix := linalg.NewCSRMatrixFromConnectivity(mesh.FaceStarts,
		mesh.NeighbourIndices)
	matrixInternal := linalg.NewCSRMatrixFromConnectivity(mesh.FaceStarts,
		mesh.NeighbourIndices)

	rhs := make(linalg.Vector, mesh.NumCells())

	boundaryDiag := make(linalg.Vector, mesh.NumBoundaries())
	boundaryOffDiag := make(linalg.Vector, mesh.NumBoundaries())

	return &scalarEquation{
		owner: owner,
		bcs:   bcs,
		mesh:  mesh,
		dt:    math.MaxFloat32,

		fluxOps:   fluxOps,
		sourceOps: sourceOps,

		matrix:          matrix,
		matrixInternal:  matrixInternal,
		rhs:             rhs,
		boundaryDiag:    boundaryDiag,
		boundaryOffDiag: boundaryOffDiag,
	}, nil
}

func (sed *scalarEquationDefinition) rank() rank { return scalar }

// DEFINITION FACTORY

func NewEquation(owner FieldDefinition, operators ...OperatorDefinition,
) (EquationDefinition, error) {
	switch field := owner.(type) {
	case *scalarFieldDefinition:
		return newScalarEquationDefinition(field, operators...)
	default:
		return nil, fmt.Errorf("NewEquation > could not create an equation for field of type '%T'",
			field)
	}
}

// RESOLVED

type scalarEquation struct {
	owner *scalarField
	bcs   []*scalarBC
	mesh  *geometry.Mesh
	dt    float32

	fluxOps   []*scalarOperator
	sourceOps []*scalarOperator

	matrix          *linalg.CSR
	matrixInternal  *linalg.CSR
	rhs             linalg.Vector
	boundaryDiag    linalg.Vector
	boundaryOffDiag linalg.Vector
}

func (se *scalarEquation) rank() rank { return scalar }

func (se *scalarEquation) advanceTime(dt float32) {
	se.dt = dt
}

func (se *scalarEquation) runFluxOperators() {
	se.matrixInternal.Wipe()
	se.boundaryDiag.Wipe()
	se.boundaryOffDiag.Wipe()

	for _, op := range se.fluxOps {
		proc := scalarOpProcedureTable[op.opType]
		proc(op, se.mesh, se)
	}
}

func (se *scalarEquation) assembleSystem() *linalg.System {
	se.matrix.CopyFrom(se.matrixInternal)
	se.rhs.Wipe()

	for _, op := range se.sourceOps {
		proc := scalarOpProcedureTable[op.opType]
		proc(op, se.mesh, se)
	}

	for _, bc := range se.bcs {
		proc := scalarBCProcedureTable[bc.bcType]
		proc(bc, se.owner, se)
	}

	return &linalg.System{A: se.matrix, B: se.rhs}
}
