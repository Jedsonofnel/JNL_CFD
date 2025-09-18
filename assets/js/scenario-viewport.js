import {
	createBuffer,
	createShaderProgram,
	updateBuffer,
} from "./lib/webgl-helper.js";

export class ScenarioViewport {
	constructor(element) {
		this.container = element;
		this.canvas = element.querySelector("[data-js-viewport-canvas]");
		this.dataFieldset = element.querySelector("[data-js-viewport-data]");

		this.gl = null;
		this.program = null;
		this.positionBuffer = null;
		this.colourBuffer = null;
		this.positionLocation = null;
		this.colourLocation = null;
		this.numVertices = 0;

		this.setupWebGL();

		this.scenarioWorker = new Worker(
			new URL("./workers/run-scenario.js", import.meta.url),
			{ type: "module" },
		);

		this.scenarioWorker.onmessage = ({ data }) => {
			switch (data.type) {
				case "geometry":
					this.setupCanvas(data.metadata.width, data.metadata.height);
					this.setupGeometry(data.vertices);
					break;
				case "frame":
					this.updateColours(data.colourScales);
					break;
				case "frameRate":
					console.log(`FPS: ${data.value}`);
					break;
				default:
					console.error(
						"main thread cannot respond to message type: ",
						data.type,
					);
			}
		};

		this.scenarioWorker.onerror = (error) => {
			console.error("worker error: ", error.message);
		};

		this.registerButtons();
		this.setupViz();
	}

	setupWebGL() {
		this.gl =
			this.canvas.getContext("webgl2") || this.canvas.getContext("webgl");

		this.program = createShaderProgram(
			this.gl,
			vertexShader2d,
			fragmentShader2d,
		);

		this.positionLocation = this.gl.getAttribLocation(
			this.program,
			"a_position",
		);
		this.colourLocation = this.gl.getAttribLocation(
			this.program,
			"colourScale",
		);
	}

	setupCanvas(width, height) {
		const aspectRatio = width / height;
		this.canvas.height = this.canvas.width / aspectRatio;

		this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
	}

	setupGeometry(vertices) {
		if (this.positionBuffer) this.gl.deleteBuffer(this.positionBuffer);
		if (this.colourBuffer) this.gl.deleteBuffer(this.colourBuffer);

		this.positionBuffer = createBuffer(this.gl, vertices);
		this.numVertices = vertices.length / 2;

		this.colourBuffer = this.gl.createBuffer();
		this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.colourBuffer);
		this.gl.bufferData(
			this.gl.ARRAY_BUFFER,
			new Float32Array(this.numVertices),
			this.gl.DYNAMIC_DRAW,
		);
	}

	updateColours(colourScales) {
		updateBuffer(this.gl, this.colourBuffer, colourScales);
		this.render();
	}

	render() {
		this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
		this.gl.useProgram(this.program);

		this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.positionBuffer);
		this.gl.enableVertexAttribArray(this.positionLocation);
		this.gl.vertexAttribPointer(
			this.positionLocation,
			2,
			this.gl.FLOAT,
			false,
			0,
			0,
		);

		this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.colourBuffer);
		this.gl.enableVertexAttribArray(this.colourLocation);
		this.gl.vertexAttribPointer(
			this.colourLocation,
			1,
			this.gl.FLOAT,
			false,
			0,
			0,
		);

		this.gl.drawArrays(this.gl.TRIANGLES, 0, this.numVertices);
	}

	registerButtons() {
		this.startButton = this.container.querySelector(
			`[data-js-viewport-button="start"]`,
		);
		this.startButton.addEventListener("click", this.startViz.bind(this));

		this.stopButton = this.container.querySelector(
			`[data-js-viewport-button="stop"]`,
		);
		this.stopButton.addEventListener("click", this.stopViz.bind(this));

		this.resetButton = this.container.querySelector(
			`[data-js-viewport-button="reset"]`,
		);
		this.resetButton.addEventListener("click", this.setupViz.bind(this));
	}

	setupViz() {
		if (!this.dataFieldset) return null;

		const inputs = Array.from(this.dataFieldset.querySelectorAll("input"));

		const scenarioParams = Object.fromEntries(
			inputs.map((input) => [
				input.name,
				input.type === "number" ? parseFloat(input.value) : input.value,
			]),
		);

		this.scenarioWorker.postMessage({ type: "reset", params: scenarioParams });

		this.startButton.disabled = false;
		this.stopButton.disabled = true;
		this.resetButton.disabled = false;
	}

	startViz() {
		this.scenarioWorker.postMessage({ type: "start" });

		this.startButton.disabled = true;
		this.stopButton.disabled = false;
		this.resetButton.disabled = true;
	}

	stopViz() {
		this.scenarioWorker.postMessage({ type: "stop" });
		this.startButton.disabled = false;
		this.stopButton.disabled = true;
		this.resetButton.disabled = false;
	}
}

const vertexShader2d = /* glsl */ `
	attribute vec2 a_position;
	attribute float colourScale;
	varying float vColourScale;
	void main() {
		gl_Position = vec4(a_position, 0.0, 1.0);
		vColourScale = colourScale;
	}
`;

const fragmentShader2d = /* glsl*/ `
	precision mediump float;
	varying float vColourScale;
	uniform vec4 u_colour;
	void main() {
		gl_FragColor = vec4(vColourScale, 0.0, 1.0-vColourScale, 1.0);
	}
`;
