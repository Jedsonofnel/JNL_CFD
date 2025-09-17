package geometry

type MeshRenderData struct {
	LineVertices []float32
}

func NewMeshRenderData(mesh *Mesh) *MeshRenderData {
	totalLineVertices := 0

	for i := range mesh.NumCells() {
		startIdx, endIdx := mesh.FaceStarts[i], mesh.FaceStarts[i+1]
		numLines := endIdx - startIdx
		totalLineVertices += (numLines * 2) // two vertices per line
	}

	lineVertices := make([]float32, totalLineVertices*2) // interleaved x,y,x,y,...

	vIdx := 0
	sfX, sfY := mesh.Bounds.Width/2, mesh.Bounds.Height/2

	for i := range mesh.NumCells() {
		startIdx, endIdx := mesh.FaceStarts[i], mesh.FaceStarts[i+1]
		for f := startIdx; f < endIdx; f++ {
			localVIdx := mesh.VertexIndices[f]
			physVX, physVY := mesh.VerticesX[localVIdx], mesh.VerticesY[localVIdx]
			clipVX, clipVY := transformToClipSpace(physVX, physVY, sfX, sfY)

			lineVertices[vIdx*2] = clipVX   // x
			lineVertices[vIdx*2+1] = clipVY // y

			nextVIdx := mesh.VertexIndices[startIdx] // loop back round
			if f != endIdx-1 { // or get the next
				nextVIdx = mesh.VertexIndices[f+1]
			}

			vIdx += 1

			physVX, physVY = mesh.VerticesX[nextVIdx], mesh.VerticesY[nextVIdx]
			clipVX, clipVY = transformToClipSpace(physVX, physVY, sfX, sfY)

			lineVertices[vIdx*2] = clipVX
			lineVertices[vIdx*2+1] = clipVY

			vIdx += 1
		}
	}

	// set all the lin

	return &MeshRenderData{
		LineVertices: lineVertices,
	}
}

func transformToClipSpace(vX, vY, sfX, sfY float32) (float32, float32) {
	// sfX and sfY are physical dims / 2 which means they correspond to
	// originTransformation vector components AND 1/scale for transformation
	// to new 1, 1, -1, -1 space.
	return (vX - sfX) / sfX, (vY - sfY) / sfY
}
