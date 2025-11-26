package geometry

type MeshRenderData struct {
	LineVertices []float32

	TriangleVertices []float32
	TriangleStarts   []int

	// metadata
	Width, Height float32
}

func NewMeshRenderData(mesh *Mesh) *MeshRenderData {
	lineVertices := calculateLineVertices(mesh)
	triangleVertices, triangleStarts := calculateMeshTriangulation(mesh)

	return &MeshRenderData{
		LineVertices: lineVertices,

		TriangleVertices: triangleVertices,
		TriangleStarts:   triangleStarts,

		Width:  mesh.Bounds.Width,
		Height: mesh.Bounds.Height,
	}
}

func calculateMeshTriangulation(mesh *Mesh) (
	triangleVertices []float32, triangleStarts []int) {
	totalVertices := 0

	for i := range mesh.NumCells() {
		totalVertices += (mesh.FaceStarts[i+1] - mesh.FaceStarts[i] - 2) * 3
	}

	triangleVertices = make([]float32, totalVertices*2) // interleaved
	triangleStarts = make([]int, mesh.NumCells()+1)     // fenceposted

	vIdx := 0
	sfX, sfY := mesh.Bounds.Width/2, mesh.Bounds.Height/2

	for i := range mesh.NumCells() {
		startIdx, endIdx := mesh.FaceStarts[i], mesh.FaceStarts[i+1]
		hubVertexIdx := mesh.VertexIndices[startIdx]
		triangleStarts[i] = vIdx

		// fan triangulation
		for j := startIdx + 1; j < endIdx-1; j++ {
			v1, v2, v3 := hubVertexIdx, mesh.VertexIndices[j], mesh.VertexIndices[j+1]

			cv1X, cv1Y := transformToClipSpace(mesh.Vertices[v1].X, mesh.Vertices[v1].Y, sfX, sfY)
			triangleVertices[vIdx*2] = cv1X
			triangleVertices[vIdx*2+1] = cv1Y
			vIdx++

			cv2X, cv2Y := transformToClipSpace(mesh.Vertices[v2].X, mesh.Vertices[v2].Y, sfX, sfY)
			triangleVertices[vIdx*2] = cv2X
			triangleVertices[vIdx*2+1] = cv2Y
			vIdx++

			cv3X, cv3Y := transformToClipSpace(mesh.Vertices[v3].X, mesh.Vertices[v3].Y, sfX, sfY)
			triangleVertices[vIdx*2] = cv3X
			triangleVertices[vIdx*2+1] = cv3Y
			vIdx++
		}

	}

	triangleStarts[mesh.NumCells()] = len(triangleVertices) / 2

	return
}

func calculateLineVertices(mesh *Mesh) (lineVertices []float32) {
	totalLineVertices := 0

	for i := range mesh.NumCells() {
		startIdx, endIdx := mesh.FaceStarts[i], mesh.FaceStarts[i+1]
		numLines := endIdx - startIdx
		totalLineVertices += (numLines * 2) // two vertices per line
	}

	lineVertices = make([]float32, totalLineVertices*2) // interleaved x,y,x,y,...

	vIdx := 0
	sfX, sfY := mesh.Bounds.Width/2, mesh.Bounds.Height/2

	for i := range mesh.NumCells() {
		startIdx, endIdx := mesh.FaceStarts[i], mesh.FaceStarts[i+1]
		for f := startIdx; f < endIdx; f++ {
			localVIdx := mesh.VertexIndices[f]
			physVX, physVY := mesh.Vertices[localVIdx].X, mesh.Vertices[localVIdx].Y
			clipVX, clipVY := transformToClipSpace(physVX, physVY, sfX, sfY)

			lineVertices[vIdx*2] = clipVX   // x
			lineVertices[vIdx*2+1] = clipVY // y

			nextVIdx := mesh.VertexIndices[startIdx] // loop back round
			if f != endIdx-1 {                       // or get the next
				nextVIdx = mesh.VertexIndices[f+1]
			}

			vIdx += 1

			physVX, physVY = mesh.Vertices[nextVIdx].X, mesh.Vertices[nextVIdx].Y
			clipVX, clipVY = transformToClipSpace(physVX, physVY, sfX, sfY)

			lineVertices[vIdx*2] = clipVX
			lineVertices[vIdx*2+1] = clipVY

			vIdx += 1
		}
	}

	return
}

func transformToClipSpace(vX, vY, sfX, sfY float32) (float32, float32) {
	// sfX and sfY are physical dims / 2 which means they correspond to
	// originTransformation vector components AND 1/scale for transformation
	// to new 1, 1, -1, -1 space.
	return (vX - sfX) / sfX, (vY - sfY) / sfY
}
