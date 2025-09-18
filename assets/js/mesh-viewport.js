export class MeshViewport {
	constructor(element) {
		this.container = element;
		this.canvas = element.querySelector("[data-js-viewport-canvas]");
		this.dataFieldset = element.querySelector("[data-js-viewport-data]");

		this.meshFetcher = new Worker(
			new URL("./workers/fetch-mesh-data.js", import.meta.url),
			{ type: "module" },
		);

		this.meshFetcher.onmessage = ({ data }) => {
			const { vertices } = data;
			this.renderMesh(vertices);
		};
		this.meshFetcher.onerror = (error) => {
			console.error("worker error: ", error.message);
		};

		this.displayMesh();
		this.registerButtons();
	}

	displayMesh() {
		const meshData = this.getMeshData();
		this.resizeCanvas(meshData);

		this.meshFetcher.postMessage(meshData);
	}

	registerButtons() {
		const reloadButton = this.container.querySelector(
			`[data-js-viewport-button="reload"]`,
		);
		reloadButton.addEventListener("click", this.displayMesh.bind(this));
	}

	getMeshData() {
		if (!this.dataFieldset) return null;

		const inputs = Array.from(this.dataFieldset.querySelectorAll("input"));

		return Object.fromEntries(
			inputs.map((input) => [
				input.name,
				input.type === "number" ? parseFloat(input.value) : input.value,
			]),
		);
	}

	resizeCanvas(meshData) {
		if (!meshData.width || !meshData.height) {
			console.error(
				"Could not get width or height from mesh form: ",
				this.meshData,
			);
		}

		const aspectRatio = meshData.width / meshData.height;
		this.canvas.height = this.canvas.width / aspectRatio;
	}

	renderMesh(vertices) {
		const gl = this.canvas.getContext("webgl");
		const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertexShader2d);
		const fragmentShader = createShader(
			gl,
			gl.FRAGMENT_SHADER,
			fragmentShader2d,
		);
		const program = createProgram(gl, vertexShader, fragmentShader);

		// setting up state
		const positionAttributeLocation = gl.getAttribLocation(
			program,
			"a_position",
		);
		const positionBuffer = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
		gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

		// rendering code ("hot" loop)
		gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);

		gl.clearColor(0, 0, 0, 0);
		gl.clear(gl.COLOR_BUFFER_BIT);

		gl.useProgram(program);
		gl.enableVertexAttribArray(positionAttributeLocation);

		gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);

		const colorUniformLocation = gl.getUniformLocation(program, "u_color");
		gl.uniform4f(colorUniformLocation, 0, 0, 0, 1);

		const size = 2;
		const type = gl.FLOAT;
		const normalize = false;
		const stride = 0;
		const offset = 0;
		gl.vertexAttribPointer(
			positionAttributeLocation,
			size,
			type,
			normalize,
			stride,
			offset,
		);

		const primitiveType = gl.LINES;
		const count = vertices.length / 2;
		gl.drawArrays(primitiveType, offset, count);
	}
}

function createShader(gl, type, src) {
	const shader = gl.createShader(type);
	gl.shaderSource(shader, src);
	gl.compileShader(shader);

	const success = gl.getShaderParameter(shader, gl.COMPILE_STATUS);
	if (success) {
		return shader;
	}

	console.log(gl.getShaderInfoLog(shader));
	gl.deleteShader(shader);
}

const vertexShader2d = /* glsl */ `
	attribute vec4 a_position;

	void main() {
		gl_Position = a_position;
	}
`;

const fragmentShader2d = /* glsl */ `
	precision mediump float;

	uniform vec4 u_color;
	
	void main() {
		gl_FragColor = u_color;
	}
`;

function createProgram(gl, vertexShader, fragmentShader) {
	const program = gl.createProgram();
	gl.attachShader(program, vertexShader);
	gl.attachShader(program, fragmentShader);
	gl.linkProgram(program);

	const success = gl.getProgramParameter(program, gl.LINK_STATUS);
	if (success) {
		return program;
	}

	console.log(gl.getProgramInfoLog(program));
	gl.deleteProgram(program);
}
