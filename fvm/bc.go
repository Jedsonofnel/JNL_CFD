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
	eq *Equation,
	ctx jnl.Map,
	boundaryName string,
	value float64,
) *Equation {
	meshVal := ctx.Lookup(jnl.NewKeyword("mesh"))
	mesh := meshVal.(*geometry.Mesh)
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)

	eq.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if boundaryMarker != marker {
			return
		}

		localOwner := eq.GetLocalCellIndex(owner)
		_, lower := eq.GetBoundaryFlux(boundaryIdx)

		eq.Diag[localOwner] += lower
		eq.Source[localOwner] += lower * value
	})

	return eq
}

// NeumannBC sets a fixed flux at a boundary
func NeumannBC(
	eq *Equation,
	ctx jnl.Map,
	boundaryName string,
	flux float64,
) *Equation {
	meshVal := ctx.Lookup(jnl.NewKeyword("mesh"))
	mesh := meshVal.(*geometry.Mesh)
	boundaryMarker := findBoundaryMarker(mesh, boundaryName)

	eq.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
		if boundaryMarker != marker {
			return
		}
		localOwner := eq.GetLocalCellIndex(owner)
		eq.Source[localOwner] += flux
	})

	return eq
}

// RobinBC implements a mixed boundary condition: alpha*phi + flux = gamma
// Where flux is the normal gradient flux at the boundary
// For convection: alpha=h, gamma=h*Tinf
// func RobinBC(
// 	eq *Equation,
// 	ctx *Context,
// 	boundaryName string,
// 	alpha float64, // coefficient of phi (e.g., h for convection)
// 	gamma float64, // RHS value (e.g., h*Tinf)
// ) *Equation {
// 	mesh := ctx.Mesh
// 	boundaryMarker := findBoundaryMarker(mesh, boundaryName)
// 
// 	eq.ForEachBoundaryConnection(func(boundaryIdx, globalIdx, owner, marker int) {
// 		if boundaryMarker != marker {
// 			return
// 		}
// 
// 		localOwner := eq.GetLocalCellIndex(owner)
// 
// 		// Get accumulated fluxes from operators (diffusion, convection, etc.)
// 		_, lower := eq.GetBoundaryFlux(boundaryIdx)
// 
// 		// Mixed BC discretization:
// 		// alpha*(phi_cell) + lower*(phi_boundary - phi_cell) = gamma
// 		// Solve for phi_boundary and substitute back:
// 		// effective_coeff = (lower * alpha) / (lower + alpha)
// 
// 		effectiveCoeff := (lower * alpha) / (lower + alpha)
// 
// 		eq.Diag[localOwner] += effectiveCoeff
// 		eq.Source[localOwner] += effectiveCoeff * (gamma / alpha)
// 	})
// 
// 	return eq
// }
// 
// // ConvectionBC is a helper for thermal convection: q = h(T - Tinf)
// func ConvectionBC(eq *Equation, ctx *Context,
// 	boundaryName string, h, Tinf float64) *Equation {
// 	return RobinBC(eq, ctx, boundaryName, h, h*Tinf)
// }

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
