package fvm

import (
	"fmt"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

func init() {
	jnlisp.RegisterLibrary(jnlisp.Library{
		Name: "cfd/fvm",
		Bindings: map[string]jnlisp.ProcFunc{
			"prognostic-scalar-field": lispPrognosticScalarField,
			"derived-vector-field":    lispDerivedVectorField,

			"ddt":       lispDDTOperator,
			"div":       lispDivOperator,
			"laplacian": lispLaplacianOperator,

			"scalar-point-src": lispScalarPointSource,

			"equation": lispEquation,

			"scalar-dirichlet": lispScalarDirichlet,
			"scalar-neumann":   lispScalarNeumann,
			"scalar-outflow":   lispScalarOutflow,

			"set-boundary-conditions": lispSetBoundaryConditions,

			"passive-transport": lispPassiveTransportScenario,
		},
		Atoms: map[string]jnlisp.Atom{},
	})
}

// FIELDS

type FieldDefinitionAtom struct{ Value FieldDefinition }

func (fd FieldDefinitionAtom) Type() string {
	return "cfd/fvm.FieldDefinition"
}

func (fd FieldDefinitionAtom) String() string {
	name := fd.Value.getName()
	switch r := fd.Value.rank(); r {
	case scalar:
		return "cfd/fvm.FieldDefinition (scalar): " + name
	case vector:
		return "cfd/fvm.FieldDefinition (vector): " + name
	default:
		return "cfd/fvm.FieldDefinition " + name
	}
}

func (fd FieldDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  fd.Type(),
		"value": "INTERFACE TYPE",
		"repr":  fd.String(),
	}
}

func lispPrognosticScalarField(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	name, v := jnlisp.ValidateArgs(args, kwargs).GetString()
	initialValue, v := v.GetKeywordFloat32("initial-value")

	v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	fd := NewPrognosticScalarField(name, initialValue)
	return FieldDefinitionAtom{fd}, nil
}

func lispDerivedVectorField(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	name, v := jnlisp.ValidateArgs(args, kwargs).GetString()
	timeFunc, v := v.GetProcedure()

	v = v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	cb := func(t float32) Vec2 {
		timeAtom := jnlisp.NumberAtom{Value: t}
		result, err := timeFunc.Call([]jnlisp.Atom{timeAtom}, nil, nil)

		if err != nil {
			return Vec2{}
		}

		if vecAtom, ok := jnlisp.As[jnlisp.VectorAtom](result); ok {
			if vec2, err := lispVectorToVec2(vecAtom); err == nil {
				return vec2
			}
		}

		return Vec2{}
	}

	vf := NewDerivedVectorField(name, cb)
	return FieldDefinitionAtom{vf}, nil
}

// OPERATORS

type OperatorDefinitionAtom struct{ Value OperatorDefinition }

func (od OperatorDefinitionAtom) Type() string {
	return "cfd/fvm.OperatorDefinition"
}

func (od OperatorDefinitionAtom) String() string {
	typString := opTypeStrings[od.Value.operatorType()]
	switch r := od.Value.rank(); r {
	case scalar:
		return "cfd/fvm.OperatorDefinition (scalar): " + typString
	case vector:
		return "cfd/fvm.OperatorDefinition (vector): " + typString
	default:
		return "cfd/fvm.OperatorDefinition " + typString
	}
}

func (od OperatorDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  od.Type(),
		"value": "INTERFACE TYPE",
		"repr":  od.String(),
	}
}

func lispDDTOperator(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs)
	owner, v := jnlisp.Get[FieldDefinitionAtom](v)
	coeffAtoms, v := v.GetVariadicAtoms()

	v = v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	coeffs, err := parseOperatorCoeffs(coeffAtoms)
	if err != nil {
		return nil, fmt.Errorf("ddt operator definition > %w", err)
	}

	ddt := NewDDT(owner.Value, coeffs...)
	return OperatorDefinitionAtom{ddt}, nil
}

func lispDivOperator(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs)
	owner, v := jnlisp.Get[FieldDefinitionAtom](v)
	coeffAtoms, v := v.GetVariadicAtoms()

	v = v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	coeffs, err := parseOperatorCoeffs(coeffAtoms)
	if err != nil {
		return nil, fmt.Errorf("div operator definition > %w", err)
	}

	div := NewDiv(owner.Value, coeffs...)
	return OperatorDefinitionAtom{div}, nil
}

func lispLaplacianOperator(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, nil)
	owner, v := jnlisp.Get[FieldDefinitionAtom](v)
	coeffAtoms, v := v.GetVariadicAtoms()

	v = v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	coeffs, err := parseOperatorCoeffs(coeffAtoms)
	if err != nil {
		return nil, fmt.Errorf("laplacian operator definition > %w", err)
	}

	laplacian := NewLaplacian(owner.Value, coeffs...)
	return OperatorDefinitionAtom{laplacian}, nil
}

func lispScalarPointSource(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	pos, v := jnlisp.ValidateArgs(args, nil).GetVector()
	strength, v := v.GetFloat32()
	v.ExpectNoMoreArgs()

	if err := v.Validate(); err != nil {
		return nil, err
	}

	vec2, err := lispVectorToVec2(pos)
	if err != nil {
		return nil, fmt.Errorf("scalar point source definition > %w", err)
	}

	psHandler := NewScalarPointSourceHandler()
	ps := NewScalarPointSource(psHandler)
	if err = psHandler.SetPointSource(vec2.X, vec2.Y, strength); err != nil {
		return nil, fmt.Errorf("scalar point source definition > %w", err)
	}

	return OperatorDefinitionAtom{ps}, nil
}

// EQUATIONS

type EquationDefinitionAtom struct{ Value EquationDefinition }

func (od EquationDefinitionAtom) Type() string {
	return "cfd/fvm.EquationDefinition"
}

func (od EquationDefinitionAtom) String() string {
	switch r := od.Value.rank(); r {
	case scalar:
		return "cfd/fvm.EquationDefinition (scalar)"
	case vector:
		return "cfd/fvm.EquationDefinition (vector)"
	default:
		return "cfd/fvm.EquationDefinition"
	}
}

func (od EquationDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  od.Type(),
		"value": "INTERFACE TYPE",
		"repr":  od.String(),
	}
}

func lispEquation(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, nil)
	owner, v := jnlisp.Get[FieldDefinitionAtom](v)
	opAtoms, v := jnlisp.GetVariadic[OperatorDefinitionAtom](v)
	v.ExpectNoMoreArgs()

	if err := v.Validate(); err != nil {
		return nil, err
	}

	var ops []OperatorDefinition
	for _, op := range opAtoms {
		ops = append(ops, op.Value)
	}

	eq, err := NewEquation(owner.Value, ops...)
	if err != nil {
		return nil, err
	}

	return EquationDefinitionAtom{eq}, nil
}

// BOUNDARY CONDITIONS

type BCDefinitionAtom struct{ Value BCDefinition }

func (od BCDefinitionAtom) Type() string {
	return "cfd/fvm.BCDefinition"
}

func (od BCDefinitionAtom) String() string {
	switch r := od.Value.rank(); r {
	case scalar:
		return "cfd/fvm.BCDefinition (scalar)"
	case vector:
		return "cfd/fvm.BCDefinition (vector)"
	default:
		return "cfd/fvm.BCDefinition"
	}
}

func (od BCDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  od.Type(),
		"value": "INTERFACE TYPE",
		"repr":  od.String(),
	}
}

func lispScalarDirichlet(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	num, v := jnlisp.ValidateArgs(args, kwargs).GetFloat32()

	v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	bc := ScalarDirichlet{num}
	return BCDefinitionAtom{bc}, nil
}

func lispScalarNeumann(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	num, v := jnlisp.ValidateArgs(args, kwargs).GetFloat32()

	v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	bc := ScalarNeumann{num}
	return BCDefinitionAtom{bc}, nil
}

func lispScalarOutflow(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs).ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	bc := ScalarOutflow{}
	return BCDefinitionAtom{bc}, nil
}

func lispSetBoundaryConditions(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs)
	ownerAtom, v := jnlisp.Get[EquationDefinitionAtom](v)
	meshAtom, v := jnlisp.Get[geometry.MeshDefinitionAtom](v)

	bcMap := make(map[string]BCDefinition)
	for key, atom := range kwargs {
		if bc, ok := atom.(BCDefinitionAtom); ok {
			bcMap[key] = bc.Value
		} else {
			return nil, fmt.Errorf("set-boundary-conditions > expected BCDefinition but got %s", atom.Type())
		}
	}

	v = v.ExpectNoMoreArgs()

	eq := ownerAtom.Value
	if err := eq.SetBoundaryConditions(meshAtom.Value, bcMap); err != nil {
		return nil, fmt.Errorf("set-boundary-conditions > %w", err)
	}

	return EquationDefinitionAtom{eq}, nil
}

// SIMULATION

type ScenarioDefinitionAtom struct{ Value ScenarioDefinition }

func (od ScenarioDefinitionAtom) Type() string {
	return "cfd/fvm.ScenarioDefinition"
}

func (od ScenarioDefinitionAtom) String() string {
	return "cfd/fvm.ScenarioDefinition"
}

func (od ScenarioDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  od.Type(),
		"value": "INTERFACE TYPE",
		"repr":  od.String(),
	}
}

func lispPassiveTransportScenario(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs)
	mdAtom, v := jnlisp.GetKeyword[geometry.MeshDefinitionAtom](v, "mesh")
	solverAtom, v := jnlisp.GetKeyword[linalg.SolverDefinitionAtom](v, "solver")
	fieldsVecAtom, v := v.GetKeywordVector("fields")
	eqsVecAtom, v := v.GetKeywordVector("equations")

	v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	var fields []FieldDefinition
	for _, atom := range fieldsVecAtom.Elements {
		fieldAtom, ok := jnlisp.As[FieldDefinitionAtom](atom)
		if !ok {
			return nil, fmt.Errorf("unexpected type %s in fields, expected FieldDefinition type", atom.Type())
		}
		fields = append(fields, fieldAtom.Value)
	}

	var eqs []EquationDefinition
	for _, atom := range eqsVecAtom.Elements {
		eqAtom, ok := jnlisp.As[EquationDefinitionAtom](atom)
		if !ok {
			return nil, fmt.Errorf("unexpected type %s in fields, expected EquationDefinition type", atom.Type())
		}
		eqs = append(eqs, eqAtom.Value)
	}

	sd := NewPassiveTransportScenario(mdAtom.Value, solverAtom.Value, fields, eqs)
	return ScenarioDefinitionAtom{sd}, nil
}

// helper

func parseOperatorCoeffs(coeffAtoms []jnlisp.Atom) ([]any, error) {
	var coeffs []any
	for _, atom := range coeffAtoms {
		if numAtom, ok := jnlisp.As[jnlisp.NumberAtom](atom); ok {
			switch c := numAtom.Value.(type) {
			case int, float32, float64:
				coeffs = append(coeffs, c)
			default:
				return nil, fmt.Errorf("expects rational number in operator coefficient, got %T", c)
			}
		} else if fieldAtom, ok := jnlisp.As[FieldDefinitionAtom](atom); ok {
			coeffs = append(coeffs, fieldAtom.Value)
		} else {
			return nil, fmt.Errorf("unexpected type in operator definition, expected field or number, got %s",
				atom.Type())
		}
	}
	return coeffs, nil
}

func lispVectorToVec2(vec jnlisp.VectorAtom) (Vec2, error) {
	if vec.Length() != 2 {
		return Vec2{}, fmt.Errorf("Vec2 requires exactly 2 elements, got %d",
			vec.Length())
	}

	// Extract X component
	xAtom, ok := jnlisp.As[jnlisp.NumberAtom](vec.Elements[0])
	if !ok {
		return Vec2{}, fmt.Errorf("Vec2 element 0 (X): expected number, got %s",
			vec.Elements[0].Type())
	}

	x, err := xAtom.ToFloat64()
	if err != nil {
		return Vec2{}, fmt.Errorf("Vec2 element 0 (X): %w", err)
	}

	// Extract Y component
	yAtom, ok := jnlisp.As[jnlisp.NumberAtom](vec.Elements[1])
	if !ok {
		return Vec2{}, fmt.Errorf("Vec2 element 1 (Y): expected number, got %s",
			vec.Elements[1].Type())
	}

	y, err := yAtom.ToFloat64()
	if err != nil {
		return Vec2{}, fmt.Errorf("Vec2 element 1: %w", err)
	}

	return Vec2{X: float32(x), Y: float32(y)}, nil
}
