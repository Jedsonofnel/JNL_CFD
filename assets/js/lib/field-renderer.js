//
// Pure rendering functions for field visualization
//
import {
	createBuffer,
	createShaderProgram,
	setupAttribute,
} from "./webgl-utils.js";

//
// Color map definitions
//
const COLOR_MAPS = {
	hot: [
		[0.0, 0.0, 1.0], // Blue (cold)
		[0.0, 1.0, 1.0], // Cyan
		[0.0, 1.0, 0.0], // Green
		[1.0, 1.0, 0.0], // Yellow
		[1.0, 0.0, 0.0], // Red (hot)
	],
	coolwarm: [
		[0.23, 0.299, 0.754], // Cool blue
		[0.865, 0.865, 0.865], // Neutral gray
		[0.706, 0.016, 0.15], // Warm red
	],
	viridis: [
		[0.267004, 0.004874, 0.329415],
		[0.282623, 0.140926, 0.457517],
		[0.253935, 0.265254, 0.529983],
		[0.206756, 0.371758, 0.553117],
		[0.163625, 0.471133, 0.558148],
		[0.127568, 0.566949, 0.550556],
		[0.134692, 0.658636, 0.517649],
		[0.266941, 0.748751, 0.440573],
		[0.477504, 0.821444, 0.318195],
		[0.741388, 0.873449, 0.149561],
		[0.993248, 0.906157, 0.143936],
	],
};

//
// Shader code
//
const VERTEX_SHADER = /* glsl */ `
	attribute vec2 a_position;
	attribute float a_value;
	
	varying float v_value;
	
	void main() {
		gl_Position = vec4(a_position, 0.0, 1.0);
		v_value = a_value;
	}
`;

// Generate fragment shader for a specific color map
function generateFragmentShader(colorMap) {
	const numColors = colorMap.length;
	
	// Build the color map as individual uniforms
	let uniformDeclarations = "";
	for (let i = 0; i < numColors; i++) {
		uniformDeclarations += `uniform vec3 u_color${i};\n`;
	}
	
	// Build the interpolation logic using if-else chain
	let interpolationCode = "vec3 color;\n";
	if (numColors === 2) {
		// Simple two-color blend
		interpolationCode += "color = mix(u_color0, u_color1, t);\n";
	} else {
		// Multi-color interpolation with if-else chain
		const stepSize = 1.0 / (numColors - 1);
		for (let i = 0; i < numColors - 1; i++) {
			const threshold = (i + 1) * stepSize;
			const lowerBound = i * stepSize;
			
			if (i === 0) {
				interpolationCode += `if (t <= ${threshold.toFixed(6)}) {\n`;
			} else {
				interpolationCode += `else if (t <= ${threshold.toFixed(6)}) {\n`;
			}
			
			interpolationCode += `    float localT = (t - ${lowerBound.toFixed(6)}) / ${stepSize.toFixed(6)};\n`;
			interpolationCode += `    color = mix(u_color${i}, u_color${i + 1}, localT);\n`;
			interpolationCode += `}\n`;
		}
		interpolationCode += `else {\n`;
		interpolationCode += `    color = u_color${numColors - 1};\n`;
		interpolationCode += `}\n`;
	}
	
	return /* glsl */ `
		precision mediump float;
		
		varying float v_value;
		${uniformDeclarations}
		
		void main() {
			float t = clamp(v_value, 0.0, 1.0);
			${interpolationCode}
			gl_FragColor = vec4(color, 1.0);
		}
	`;
}

//
// Transform field data from domain space to NDC space
//
function prepareFieldGeometry(fieldData, transform) {
	const vertices = fieldData.vertices;
	const values = fieldData.values;
	const numTriangles = vertices.length / 6; // 2 coords per vertex, 3 vertices per triangle

	const positions = new Float32Array(numTriangles * 6); // x,y for each vertex
	const vertexValues = new Float32Array(numTriangles * 3); // value for each vertex

	for (let i = 0; i < numTriangles; i++) {
		const baseIdx = i * 6;
		const valueIdx = i * 3;

		// Transform each vertex of the triangle
		for (let v = 0; v < 3; v++) {
			const x = vertices[baseIdx + v * 2];
			const y = vertices[baseIdx + v * 2 + 1];
			const [ndcX, ndcY] = transform.domainToNDC(x, y);

			positions[baseIdx + v * 2] = ndcX;
			positions[baseIdx + v * 2 + 1] = ndcY;
			vertexValues[valueIdx + v] = values[valueIdx + v];
		}
	}

	return { positions, vertexValues };
}

//
// Render field using WebGL with interpolated colors
//
export function renderField(gl, transform, fieldData, options = {}) {
	const opts = {
		colorMap: options.colorMap ?? "hot",
		clear: options.clear ?? true,
	};

	// Clear if requested
	if (opts.clear) {
		gl.clearColor(1.0, 1.0, 1.0, 1.0);
		gl.clear(gl.COLOR_BUFFER_BIT);
	}

	// Get color map
	const colorMap = COLOR_MAPS[opts.colorMap] ?? COLOR_MAPS.hot;

	// Prepare geometry in NDC space
	const { positions, vertexValues } = prepareFieldGeometry(fieldData, transform);

	if (positions.length === 0) {
		console.warn("No field data to render");
		return;
	}

	// Generate fragment shader for this color map
	const fragmentShader = generateFragmentShader(colorMap);

	// Create shader program
	const program = createShaderProgram(gl, VERTEX_SHADER, fragmentShader);
	if (!program) {
		console.error("Failed to create shader program");
		return;
	}

	gl.useProgram(program);

	// Create and bind position buffer
	const positionBuffer = createBuffer(gl, positions);
	setupAttribute(gl, program, "a_position", positionBuffer, 2);

	// Create and bind value buffer
	const valueBuffer = createBuffer(gl, vertexValues);
	setupAttribute(gl, program, "a_value", valueBuffer, 1);

	// Set color uniforms
	for (let i = 0; i < colorMap.length; i++) {
		const colorLocation = gl.getUniformLocation(program, `u_color${i}`);
		gl.uniform3fv(colorLocation, colorMap[i]);
	}

	// Draw triangles
	const numVertices = positions.length / 2;
	gl.drawArrays(gl.TRIANGLES, 0, numVertices);

	// Cleanup
	gl.deleteBuffer(positionBuffer);
	gl.deleteBuffer(valueBuffer);
	gl.deleteProgram(program);
}
