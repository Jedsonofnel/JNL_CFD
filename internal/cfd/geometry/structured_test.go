package geometry

import (
	"testing"
)

func TestNewStructuredMeshReturnsCorrectAmount(t *testing.T) {
	for _, tt := range []struct {
		name          string
		nX, nY        int
		width, height float32
		wantCells     int
	}{
		{"2x2 mesh", 2, 2, 8.0, 8.0, 4},
		{"3x2 mesh", 3, 1, 6.0, 3.0, 3},
	} {
		t.Run(tt.name, func(t *testing.T) {
			mesh := NewStructuredMesh(tt.nX, tt.nY, tt.width, tt.height)

			if got, want := mesh.NumCells(), tt.wantCells; got != want {
				t.Errorf("NumCells()=%d, want=%d", got, want)
			}
		})
	}
}

func TestNewStructuredMeshValues(t *testing.T) {
	mesh := NewStructuredMesh(3, 3, 12.0, 6.0)

	index := 0 // bottom left for structured mesh
	westIndex := mesh.neighbourStarts[index]
	southIndex, eastIndex, northIndex := westIndex+1, westIndex+2, westIndex+3

	// eg top left vertex index
	tlvi := mesh.faceStarts[index]
	tlv := mesh.faceIndices[tlvi]

	blvi, brvi, trvi := tlvi+1, tlvi+2, tlvi+3
	blv, brv, trv := mesh.faceIndices[blvi], mesh.faceIndices[brvi], mesh.faceIndices[trvi]

	// the float32s
	for _, tt := range []struct {
		name                string
		gotValue, wantValue float32
	}{
		{"centroidX", mesh.centroidsX[index], 2.0},
		{"centroidY", mesh.centroidsY[index], 1.0},
		{"cell volume", mesh.cellVolumes[index], 8.0},

		{"west face area", mesh.faceAreas[westIndex], 2.0},
		{"west neighbour distance", mesh.neighbourDistances[westIndex], 2.0},
		{"west neighour normal x", mesh.faceNormalsX[westIndex], -1.0},
		{"west neighour normal y", mesh.faceNormalsY[westIndex], 0.0},

		{"south face area", mesh.faceAreas[southIndex], 4.0},
		{"south neighbour distance", mesh.neighbourDistances[southIndex], 1.0},
		{"south neighour normal x", mesh.faceNormalsX[southIndex], 0.0},
		{"south neighour normal y", mesh.faceNormalsY[southIndex], -1.0},

		{"east face area", mesh.faceAreas[eastIndex], 2.0},
		{"east neighbour distance", mesh.neighbourDistances[eastIndex], 4.0},
		{"east neighour normal x", mesh.faceNormalsX[eastIndex], 1.0},
		{"east neighour normal y", mesh.faceNormalsY[eastIndex], 0.0},

		{"north face area", mesh.faceAreas[northIndex], 4.0},
		{"north neighbour distance", mesh.neighbourDistances[northIndex], 2.0},
		{"north neighour normal x", mesh.faceNormalsX[northIndex], 0.0},
		{"north neighour normal y", mesh.faceNormalsY[northIndex], 1.0},

		{"tl vertex x", mesh.verticesX[tlv], 0.0},
		{"bl vertex x", mesh.verticesX[blv], 0.0},
		{"br vertex x", mesh.verticesX[brv], 4.0},
		{"tr vertex x", mesh.verticesX[trv], 4.0},

		{"tl vertex y", mesh.verticesY[tlv], 2.0},
		{"bl vertex y", mesh.verticesY[blv], 0.0},
		{"br vertex y", mesh.verticesY[brv], 0.0},
		{"tr vertex y", mesh.verticesY[trv], 2.0},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got, want := tt.gotValue, tt.wantValue; got != want {
				t.Errorf("For %v, got=%v, want=%v", tt.name, got, want)
			}
		})
	}

	// neighbour types
	for _, tt := range []struct {
		name string
		gotValue, wantValue NeighbourType
	}{
		{"west neighbour type", mesh.neighbourTypes[westIndex], BorderWest},
		{"south neighbour type", mesh.neighbourTypes[southIndex], BorderSouth},
		{"east neighbour type", mesh.neighbourTypes[eastIndex], InternalBoundary},
		{"north neighbour type", mesh.neighbourTypes[northIndex], InternalBoundary},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got, want := tt.gotValue, tt.wantValue; got != want {
				t.Errorf("For %v, got=%v, want=%v", tt.name, got, want)
			}
		})
	}
}
