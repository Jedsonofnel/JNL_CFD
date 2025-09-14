package field

import (
	"fmt"
	"github.com/Jedsonofnel/cfd-but-wasm/geometry"
	"github.com/Jedsonofnel/cfd-but-wasm/linalg"
	"slices"
)

type FaceVelocityData struct {
	FVX, FVY []float32
}

type VelocityConfig struct {
	Viscocity     float32
	Density       float32
	InitialValues [2]float32
}

type Velocity struct {
	// Dependencies
	mesh          *geometry.Mesh
	bcs           map[string]VectorBC
	viscocity     float32
	density       float32
	initialValues [2]float32

	// Data arrays
	cellVelocitiesX  []float32
	cellVelocitiesY  []float32
	cellVelocitiesX0 []float32
	cellVelocitiesY0 []float32
	cellVolumes      []float32
	timeCoeffs       []float32
	sources          []VectorSource
	neighbourStarts  []int
	neighbours       []Neighbour
	neighbourIndices []int
	faceNormalsX     []float32
	faceNormalsY     []float32
	faceVelocities   []float32

	sysX linalg.System
	sysY linalg.System
}

func NewVelocityField(
	mesh *geometry.Mesh,
	config VelocityConfig,
) *Velocity {
	return &Velocity{
		mesh:          mesh,
		bcs:           make(map[string]VectorBC, len(mesh.RequiredBoundaries())),
		viscocity:     config.Viscocity,
		density:       config.Density,
		initialValues: config.InitialValues,
	}
}

func (v *Velocity) ApplyBoundaryConditions(bcs map[string]VectorBC) error {
	requiredBoundaries := v.mesh.RequiredBoundaries()

	for boundaryName, bc := range bcs {
		if !slices.Contains(requiredBoundaries, boundaryName) {
			return fmt.Errorf(
				"Cannot apply boundary condition to %v, available boundaries: %v",
				boundaryName,
				requiredBoundaries,
			)
		}
		v.bcs[boundaryName] = bc
	}

	return nil
}

func (v *Velocity) Resolve() error {
	requiredBoundaries := v.mesh.RequiredBoundaries()
	missingBCs := make([]string, 0, len(requiredBoundaries))

	for _, boundaryName := range requiredBoundaries {
		if v.bcs[boundaryName] == nil {
			missingBCs = append(missingBCs, boundaryName)
		}
	}

	if len(missingBCs) > 0 {
		return fmt.Errorf(
			"Cannot resolve field, missing boundary conditions for: %v, required: %v",
			missingBCs,
			requiredBoundaries,
		)
	}

	nCells := v.mesh.NumCells()
	if len(v.cellVelocitiesX) == nCells { // check it's not been called before
		return nil
	}

	fad := v.mesh.FieldAssemblyData()

	v.cellVelocitiesX = make([]float32, nCells)
	v.cellVelocitiesY = make([]float32, nCells)
	v.cellVelocitiesX0 = make([]float32, nCells)
	v.cellVelocitiesY0 = make([]float32, nCells)
	v.cellVolumes = fad.CellVolumes
	v.timeCoeffs = make([]float32, nCells)
	v.sources = make([]VectorSource, nCells) // TODO make a NewNoVectorSourceSlice

	nNeighbours := len(fad.CellNeighbours)
	v.neighbours = make([]Neighbour, nNeighbours) // TODO make a velocityNeighbour!
	v.neighbourStarts = fad.NeighbourStarts
	v.neighbourIndices = fad.CellNeighbours
	v.faceNormalsX = fad.FaceNormalsX
	v.faceNormalsY = fad.FaceNormalsY

	for i := range nCells {
		v.cellVelocitiesX[i] = v.initialValues[0]
		v.cellVelocitiesX0[i] = v.initialValues[0]
		v.cellVelocitiesY[i] = v.initialValues[1]
		v.cellVelocitiesY0[i] = v.initialValues[1]
		v.timeCoeffs[i] = v.density * v.cellVolumes[i]

		// TODO populate neighbours
	}

	v.faceVelocities = make([]float32, nNeighbours)
	for f := range nNeighbours {
		initialFaceVelocity := linalg.Dot2D(
			v.initialValues[0], v.initialValues[1],
			v.faceNormalsX[f], v.faceNormalsY[f],
		)
		v.faceVelocities[f] = initialFaceVelocity
	}

	v.sysX = linalg.System{
		A: linalg.NewCSRMatrixFromConnectivity(v.neighbourStarts, v.neighbourIndices),
		B: make(linalg.Vector, nCells),
	}
	v.sysY = linalg.System{
		A: linalg.NewCSRMatrixFromConnectivity(v.neighbourStarts, v.neighbourIndices),
		B: make(linalg.Vector, nCells),
	}

	return nil
}

type ScalarGradients struct {
	GradX, GradY []float32
	Field        *Scalar
}

func (v *Velocity) UpdateFaceVelocitiesWithMWI(pressures []float32, pressureGradients *ScalarGradients) []float32 {
	nCells := v.mesh.NumCells()
	diagonalsX := make([]float32, nCells)
	diagonalsY := make([]float32, nCells)

	for i := range diagonalsX {
		diagonalsX[i] = v.sysX.A.GetDiagonal(i)
		diagonalsY[i] = v.sysY.A.GetDiagonal(i)
	}

	for i := range nCells {
		for f := v.neighbourStarts[i]; f < v.neighbourStarts[i+1]; f++ {
			ni := v.neighbourIndices[f]

			dHatX := v.mesh.NeighbourNormalsX[f]
			dHatY := v.mesh.NeighbourNormalsY[f]
			nX := v.mesh.FaceNormalsX[f]
			nY := v.mesh.FaceNormalsY[f]

			vAvgX := 0.5 * (v.cellVelocitiesX[i] + v.cellVelocitiesX[ni])
			vAvgY := 0.5 * (v.cellVelocitiesY[i] + v.cellVelocitiesY[ni])
			convectiveVelocity := linalg.Dot2D(vAvgX, vAvgY, nX, nY)

			dHatXSq := dHatX * dHatX
			dHatYSq := dHatY * dHatY
			aPEff := (dHatXSq*diagonalsX[i] + dHatYSq*diagonalsY[i])
			aAEff := (dHatXSq*diagonalsX[ni] + dHatYSq*diagonalsY[ni])
			dP, dA := v.cellVolumes[i]/aPEff, v.cellVolumes[ni]/aAEff

			pressureDifferenceCorrection := 0.5 * (dP + dA) * (pressures[i] - pressures[ni]) / v.mesh.NeighbourDistances[f]

			pressureGradientCorrection := -0.5 * linalg.Dot2D(
				dP*pressureGradients.GradX[i]+dA*pressureGradients.GradX[ni],
				dP*pressureGradients.GradY[i]+dA*pressureGradients.GradY[ni],
				dHatX,
				dHatY,
			)

			vOrth := convectiveVelocity + pressureDifferenceCorrection + pressureGradientCorrection

			c := linalg.Dot2D(dHatX, dHatY, nX, nY)

			nPerpX, nPerpY := nX-c*dHatX, nY-c*dHatY

			vNonOrth := linalg.Dot2D(vAvgX, vAvgY, nPerpX, nPerpY)

			v.faceVelocities[f] = vOrth*c + vNonOrth
		}
	}

	return v.faceVelocities
}

func (v *Velocity) AssembleSystem(dt float32) (linalg.System, linalg.System) {
	nCells := v.mesh.NumCells()
	v.sysX.Wipe()
	v.sysY.Wipe()

	for range nCells {
		// TODO figure this one out
	}

	return v.sysX, v.sysY
}
