package fvm

import (
	"sort"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/linalg"
)

//
// Equation stores the transient equation for solving
//

type Equation struct {
	// Direct arrays for assembly (cache-friendly)
	Diag      []float64 // per active cell
	UpperDiag []float64 // per active connection
	LowerDiag []float64 // per active connection
	Source    []float64 // per active cell

	// boundary flux - cached per boundary connection
	BoundaryUpper []float64 // flux-coefficient "into" boundary from owner
	BoundaryLower []float64 // flux-coefficient "from" boundary to owner

	// internal mappings
	activeCells         []uint32
	activeConnections   []uint32
	boundaryConnections []uint32
	cellToLocal         map[uint32]uint32 // global cell idx -> local idx

	cachedCSR   *linalg.CSR
	csrValueMap []csrMapping // how to fill CSR values
	solutions   []float64    // scratch buffer

	mesh *geometry.Mesh
}

// Maps equation arrays to CSR value positions
type csrMapping struct {
	csrIdx int   // index in CSR.values[]
	source uint8 // 0=Diag, 1=UpperDiag, 2=LowerDiag
	srcIdx int   // index in source array
}

func NewEquation(mesh *geometry.Mesh, regions ...string) *Equation {
	var regionSet map[string]bool
	if len(regions) > 0 {
		regionSet = make(map[string]bool)
		for _, r := range regions {
			regionSet[r] = true
		}
	}

	// Find active cells
	var activeCells []uint32
	cellToLocal := make(map[uint32]uint32)

	for i, region := range mesh.CellRegions {
		regionName := mesh.RegionNames[region]

		if regionSet == nil || regionSet[regionName] {
			localIdx := uint32(len(activeCells))
			globalIdx := uint32(i)
			cellToLocal[globalIdx] = localIdx
			activeCells = append(activeCells, globalIdx)
		}
	}

	// Find active connections (both cells must be active)
	var activeConnections []uint32
	var boundaryConnections []uint32

	for i, conn := range mesh.Connections {
		ownerGlobal := uint32(conn.Owner)
		_, ownerActive := cellToLocal[ownerGlobal]
		if !ownerActive {
			continue
		}

		connIdx := uint32(i)

		if conn.Marker == 0 {
			// Internal connection - neighbour must also be active
			neighbourGlobal := uint32(conn.Neighbour)
			_, neighbourActive := cellToLocal[neighbourGlobal]

			if neighbourActive {
				activeConnections = append(activeConnections, connIdx)
			}
		} else {
			// External boundary
			boundaryConnections = append(boundaryConnections, connIdx)
		}
	}

	nActiveCells := len(activeCells)
	nActiveConns := len(activeConnections)
	nBoundaryConns := len(boundaryConnections)

	eq := &Equation{
		Diag:                make([]float64, nActiveCells),
		UpperDiag:           make([]float64, nActiveConns),
		LowerDiag:           make([]float64, nActiveConns),
		Source:              make([]float64, nActiveCells),
		BoundaryUpper:       make([]float64, nBoundaryConns),
		BoundaryLower:       make([]float64, nBoundaryConns),
		activeCells:         activeCells,
		activeConnections:   activeConnections,
		boundaryConnections: boundaryConnections,
		cellToLocal:         cellToLocal,
		mesh:                mesh,
		solutions:           make([]float64, len(mesh.Centroids)),
	}

	eq.buildCSRStructure()

	return eq
}

// Zero the equation (reuse allocation)
func (eq *Equation) Zero() {
	for i := range eq.Diag {
		eq.Diag[i] = 0
		eq.Source[i] = 0
	}
	for i := range eq.UpperDiag {
		eq.UpperDiag[i] = 0
		eq.LowerDiag[i] = 0
	}
	for i := range eq.BoundaryUpper {
		eq.BoundaryUpper[i] = 0
		eq.BoundaryLower[i] = 0
	}
}

//
// Public accessors to hide uint32 implementation
//

func (eq *Equation) NCells() int {
	return len(eq.activeCells)
}

func (eq *Equation) NConns() int {
	return len(eq.activeConnections)
}

func (eq *Equation) NBoundaryConns() int {
	return len(eq.boundaryConnections)
}

// ForEachCell iterates over active cells
// Callback receives: localIdx, globalIdx (all as int)
func (eq *Equation) ForEachCell(fn func(localIdx, globalIdx int)) {
	for localIdx, globalIdx := range eq.activeCells {
		fn(localIdx, int(globalIdx))
	}
}

// ForEachConnection iterates over active connections
// Callback receives: localConnIdx, globalConnIdx, owner, neighbour (all as int)
func (eq *Equation) ForEachConnection(fn func(localIdx, globalIdx, owner, neighbour int)) {
	for localIdx, globalIdx := range eq.activeConnections {
		conn := eq.mesh.Connections[globalIdx]
		owner := int(conn.Owner)
		neighbour := int(conn.Neighbour)

		fn(localIdx, int(globalIdx), owner, neighbour)
	}
}

// ForEachBoundaryConnection iterates over boundary connections
// Callback receives: boundaryIdx, globalConnIdx, owner, marker (all as int)
func (eq *Equation) ForEachBoundaryConnection(fn func(boundaryIdx, globalIdx, owner, marker int)) {
	for boundaryIdx, globalIdx := range eq.boundaryConnections {
		conn := eq.mesh.Connections[globalIdx]
		owner := int(conn.Owner)
		marker := int(conn.Marker)

		fn(boundaryIdx, int(globalIdx), owner, marker)
	}
}

// GetLocalCellIndex converts global cell index to local (returns -1 if not active)
func (eq *Equation) GetLocalCellIndex(globalIdx int) int {
	if local, ok := eq.cellToLocal[uint32(globalIdx)]; ok {
		return int(local)
	}
	return -1
}

// GetGlobalCellIndex converts local cell index to global
func (eq *Equation) GetGlobalCellIndex(localIdx int) int {
	return int(eq.activeCells[localIdx])
}

// AddBoundaryFlux accumulates boundary flux (handles sparse storage internally)
func (eq *Equation) AddBoundaryFlux(boundaryConnIdx int, upper, lower float64) {
	eq.BoundaryUpper[boundaryConnIdx] += upper
	eq.BoundaryLower[boundaryConnIdx] += lower
}

// GetBoundaryFlux retrieves accumulated boundary flux (returns 0 if none)
func (eq *Equation) GetBoundaryFlux(boundaryConnIdx int) (upper, lower float64) {
	return eq.BoundaryUpper[boundaryConnIdx], eq.BoundaryLower[boundaryConnIdx]
}

//
// Solving the equation
//

// // buildCSRStructure constructs the CSR sparsity pattern and mapping
// Called once during NewEquation()
func (eq *Equation) buildCSRStructure() {
	mesh := eq.mesh
	ncells := len(eq.activeCells)

	// Count non-zeros per row
	rowNonZeros := make([]int, ncells)
	for i := range ncells {
		rowNonZeros[i] = 1 // diagonal
	}

	for _, globalConnIdx := range eq.activeConnections {
		conn := mesh.Connections[globalConnIdx]
		localOwner := eq.cellToLocal[uint32(conn.Owner)]
		localNeighbour := eq.cellToLocal[uint32(conn.Neighbour)]

		rowNonZeros[localOwner]++
		rowNonZeros[localNeighbour]++
	}

	// Build rowStarts
	rowStarts := make([]int, ncells+1)
	rowStarts[0] = 0
	for i := range ncells {
		rowStarts[i+1] = rowStarts[i] + rowNonZeros[i]
	}

	totalNonZeros := rowStarts[ncells]
	columns := make([]int, totalNonZeros)
	values := make([]float64, totalNonZeros) // will be filled by ToCSR()
	csrValueMap := make([]csrMapping, totalNonZeros)

	// Build each row's column indices and mappings
	type colEntry struct {
		col     int
		mapping csrMapping
	}

	rowEntries := make([][]colEntry, ncells)
	for i := range ncells {
		rowEntries[i] = make([]colEntry, 0, rowNonZeros[i])
	}

	// Add diagonal entries
	for i := range ncells {
		rowEntries[i] = append(rowEntries[i], colEntry{
			col: i,
			mapping: csrMapping{
				source: 0, // Diag
				srcIdx: i,
			},
		})
	}

	// Add off-diagonal entries from connections
	for localConnIdx, globalConnIdx := range eq.activeConnections {
		conn := mesh.Connections[globalConnIdx]

		localOwner := int(eq.cellToLocal[uint32(conn.Owner)])
		localNeighbour := int(eq.cellToLocal[uint32(conn.Neighbour)])

		// Owner row gets UpperDiag (coefficient of φ_neighbour)
		rowEntries[localOwner] = append(rowEntries[localOwner], colEntry{
			col: localNeighbour,
			mapping: csrMapping{
				source: 1, // UpperDiag
				srcIdx: localConnIdx,
			},
		})

		// Neighbour row gets LowerDiag (coefficient of φ_owner)
		rowEntries[localNeighbour] = append(rowEntries[localNeighbour], colEntry{
			col: localOwner,
			mapping: csrMapping{
				source: 2, // LowerDiag
				srcIdx: localConnIdx,
			},
		})
	}

	// Sort and flatten into CSR arrays
	for i := range ncells {
		sort.Slice(rowEntries[i], func(a, b int) bool {
			return rowEntries[i][a].col < rowEntries[i][b].col
		})

		startIdx := rowStarts[i]
		for j, e := range rowEntries[i] {
			csrIdx := startIdx + j
			columns[csrIdx] = e.col
			csrValueMap[csrIdx] = e.mapping
			// csrValueMap remembers: csrIdx comes from source/srcIdx
		}
	}

	eq.cachedCSR = linalg.NewCSRFromArrays(values, columns, rowStarts)
	eq.csrValueMap = csrValueMap
}

func (eq *Equation) Solve(solver linalg.Solver, ctx *Context, fieldName string) {
	field := ctx.Fields[fieldName]
	if field.IsScalar() {
		panic("cannot solve equation into constant field")
	}

	// Extract initial guess from field at active cells
	for i, globalIdx := range eq.activeCells {
		eq.solutions[i] = field.Values[globalIdx]
	}

	// Solve into scratch buffer
	eq.updateCSRValues()
	solver.Solve(eq.getCSR(), eq.Source, eq.solutions)

	// Write back to field
	for i, globalIdx := range eq.activeCells {
		field.Values[globalIdx] = eq.solutions[i]
	}
}

// updateCSRValues updates the CSR matrix (zero-allocation)
func (eq *Equation) updateCSRValues() {
	values := eq.cachedCSR.Values
	for csrIdx, mapping := range eq.csrValueMap {
		switch mapping.source {
		case 0: // Diag
			values[csrIdx] = eq.Diag[mapping.srcIdx]
		case 1: // UpperDiag
			values[csrIdx] = eq.UpperDiag[mapping.srcIdx]
		case 2: // LowerDiag
			values[csrIdx] = eq.LowerDiag[mapping.srcIdx]
		}
	}

}

func (eq *Equation) getCSR() *linalg.CSR {
	return eq.cachedCSR
}
