//
// Pure rendering functions for mesh visualisation
//

import {
	createBuffer,
	createShaderProgram,
	setupAttribute,
} from "./webgl-utils.js";

//
// Visual constants
//

const MESH_LINE_COLOR = [0.2, 0.2, 0.2, 1.0]; // Dark gray
const MESH_LINE_WIDTH = 1.0;

//
// Shader code
//

const VERTEX_SHADER = /* glsl */ `
	attribute vec2 a_position;
	
	void main() {
		gl_Position = vec4(a_position, 0.0, 1.0);
	}
`;

const FRAGMENT_SHADER = /* glsl */ `
	precision mediump float;
	uniform vec4 u_color;
	
	void main() {
		gl_FragColor = u_color;
	}
`;

//
// Extract line segments from meesh data
// returns float32Array of vertex positions in NDC space
//
function extractMeshLines(meshData, transform) {
	const vertices = meshData.vertices;
	const vertexIndices = meshData["vertex-indices"];
	const faceStarts = meshData["face-starts"];

	const numCells = faceStarts.length - 1;
	const lines = [];

	// For each cell, extract edges
	for (let cellIdx = 0; cellIdx < numCells; cellIdx++) {
		const start = faceStarts[cellIdx];
		const end = faceStarts[cellIdx + 1];
		const numVerts = end - start;

		// Connect consecutive vertices in a loop
		for (let i = 0; i < numVerts; i++) {
			const v0Idx = vertexIndices[start + i];
			const v1Idx = vertexIndices[start + ((i + 1) % numVerts)];

			// Get vertex positions (vertices is flat array: [x0, y0, x1, y1, ...])
			const x0 = vertices[v0Idx * 2];
			const y0 = vertices[v0Idx * 2 + 1];
			const x1 = vertices[v1Idx * 2];
			const y1 = vertices[v1Idx * 2 + 1];

			// Convert to NDC using transform
			const [ndc_x0, ndc_y0] = transform.domainToNDC(x0, y0);
			const [ndc_x1, ndc_y1] = transform.domainToNDC(x1, y1);

			lines.push(ndc_x0, ndc_y0, ndc_x1, ndc_y1);
		}
	}

	return new Float32Array(lines);
}

//
// Render mesh using WEBGL
//
export function renderMesh(gl, transform, meshData, options = {}) {
	const opts = {
		lineColor: options.lineColor ?? MESH_LINE_COLOR,
		lineWidth: options.lineWidth ?? MESH_LINE_WIDTH,
		clear: options.clear ?? true,
	};

	// Clear if requested
	if (opts.clear) {
		gl.clearColor(0.0, 0.0, 0.0, 0.0);
		gl.clear(gl.COLOR_BUFFER_BIT);
	}

	// Extract line segments in NDC space
	const lineVertices = extractMeshLines(meshData, transform);

	if (lineVertices.length === 0) {
		console.warn("No mesh lines to render");
		return;
	}

	// Create shader program
	const program = createShaderProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
	if (!program) {
		console.error("Failed to create shader program");
		return;
	}

	// Create and bind buffer
	const vertexBuffer = createBuffer(gl, lineVertices);

	// Setup attributes
	gl.useProgram(program);
	setupAttribute(gl, program, "a_position", vertexBuffer, 2);

	// Set line color uniform
	const colorLocation = gl.getUniformLocation(program, "u_color");
	gl.uniform4fv(colorLocation, opts.lineColor);

	// Set line width (note: might not work on all platforms for width > 1)
	gl.lineWidth(opts.lineWidth);

	// Draw lines
	const numVertices = lineVertices.length / 2;
	gl.drawArrays(gl.LINES, 0, numVertices);

	// Cleanup
	gl.deleteBuffer(vertexBuffer);
	gl.deleteProgram(program);
}
