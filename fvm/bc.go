package fvm

import (
	"github.com/Jedsonofnel/jnlcfd/geometry"
	jnl "jedn.dev/jnlisp"
)

//
// Boundary conditions - act like source terms
//

// DirichletBC sets a fixed value at a boundary
func DirichletBC(
	sys *LinearSystem,
	ctx jnl.Map,
	boundaryName string,
	value float64,
) (*LinearSystem, error) {
	mesh, err := GetMesh(ctx)
	if err != nil {
		return sys, nil
	}
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)

	sys.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if boundaryMarker != marker {
			return
		}

		localOwner := sys.GetLocalCellIndex(owner)
		_, lower := sys.GetBoundaryFlux(boundaryIdx)

		sys.Diag[localOwner] += lower
		sys.Source[localOwner] += lower * value
	})

	return sys, nil
}

// NeumannBC sets a fixed flux at a boundary
func NeumannBC(
	sys *LinearSystem,
	ctx jnl.Map,
	boundaryName string,
	flux float64,
) (*LinearSystem, error) {
	mesh, err := GetMesh(ctx)
	if err != nil {
		return sys, nil
	}
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)

	sys.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if boundaryMarker != marker {
			return
		}
		localOwner := sys.GetLocalCellIndex(owner)
		sys.Source[localOwner] += flux
	})

	return sys, nil
}

// RobinBC implements a mixed boundary condition: alpha*phi + flux = gamma
// Where flux is the normal gradient flux at the boundary
// For convection: alpha=h, gamma=h*Tinf
func RobinBC(
	sys *LinearSystem,
	ctx jnl.Map,
	boundaryName string,
	alpha float64, // coefficient of phi (e.g., h for convection)
	gamma float64, // RHS value (e.g., h*Tinf)
) (*LinearSystem, error) {
	mesh, err := GetMesh(ctx)
	if err != nil {
		return sys, nil
	}
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)

	sys.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if boundaryMarker != marker {
			return
		}

		localOwner := sys.GetLocalCellIndex(owner)

		// Get accumulated fluxes from operators (diffusion, convection, etc.)
		_, lower := sys.GetBoundaryFlux(boundaryIdx)

		// Mixed BC discretization:
		// alpha*(phi_cell) + lower*(phi_boundary - phi_cell) = gamma
		// Solve for phi_boundary and substitute back:
		effectiveCoeff := (lower * alpha) / (lower + alpha)

		sys.Diag[localOwner] += effectiveCoeff
		sys.Source[localOwner] += effectiveCoeff * (gamma / alpha)
	})

	return sys, nil
}

//
// Helpers
//

func findBoundaryMarker(mesh *geometry.Mesh, name string) int {
	for marker, boundaryName := range mesh.BoundaryNames {
		if boundaryName == name {
			return marker
		}
	}

	// TODO wrap in an error that implements Exception
	panic("boundary " + name + " not found")
}
