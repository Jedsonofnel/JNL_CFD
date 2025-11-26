package geometry

//
// Meshing cell connection
//

// This is the main thing that is looped through in CFD
type Connection struct {
	Owner     int // cell i
	Neighbour int // cell j (or -1 for external boundary)
	Face      int // face index (for geometry lookups)
	Marker    int // boundary marker (0 = internal)
}

//
// Main mesh data structure
//

type Mesh struct {
	// Topology
	Vertices    []Vec2
	Connections []Connection

	// Geometry (parallel to connections)
	FaceAreas       []float64
	FaceNormals     []Vec2
	FaceCentroids   []Vec2
	ConnectionDists []float64
	InterpWeights   []float64

	// Cell data
	CellRegions []int
	Centroids   []Vec2
	CellVolumes []float64

	// Meta
	BoundaryNames map[int]string
	RegionNames   map[int]string
}
