import {
	createBuffer,
	createShaderProgram,
	updateBuffer,
} from "../lib/webgl-helper.js";

// helper class used by onmessage at the bottom
class ScenarioRenderer {
	constructor() {
		// webgl setup
		this.canvas = null;
		this.gl = null;
		this.lineProgram = null;
		this.triangleProgram = null;
		this.triVertexLocation = null;
		this.colorScaleLocation = null;
		this.triVertexBuffer = null;
		this.colorScalesBuffer = null;
		this.numVertices = 0;

		// animation data
		this.running = false;
		this.lastTime = 0;
		this.animationId = 0;
		this.fpsTime = 0;
		this.fpsCounter = 0;

		// wasm memory management
		this.wasmInstance = null;
		this.wasmExports = null;
		this.wasmBuffer = null;
		this.structView = null;
	}

	async init() {
		await import("/assets/wasm/wasm_exec.js");

		const go = new Go();
		const wasmInstance = await WebAssembly.instantiateStreaming(
			fetch("/assets/wasm/cfd-latest.wasm"),
			go.importObject,
		);
		go.run(wasmInstance.instance);

		this.wasmInstance = wasmInstance.instance;
		this.wasmExports = this.wasmInstance.exports;
		this.wasmBuffer = this.wasmExports.memory.buffer;
		this.refreshMemoryViews();

		return this;
	}

	setupWebGL(canvas) {
		this.canvas = canvas;
		this.gl =
			this.canvas.getContext("webgl2") || this.canvas.getContext("webgl");

		this.lineProgram = createShaderProgram(
			this.gl,
			lineVertexShader,
			lineFragShader,
		);

		this.triangleProgram = createShaderProgram(
			this.gl,
			triangleVertexShader,
			triangleFragShader,
		);

		this.triVertexLocation = this.gl.getAttribLocation(
			this.triangleProgram,
			"a_position",
		);
	}

	setup() {
		const result = this.wasmExports.setupScenarioViz(0.0001);
		this.refreshMemoryViews(); // should be run after all expensive WASM calls

		const [ptr, length] = this.unpackPtrLength(result);
		const vertices = new Float32Array(this.wasmBuffer, ptr, length);

		const gl = this.gl;

		// cleanup
		if (this.triVertexBuffer) gl.deleteBuffer(this.triVertexBuffer);
		if (this.colorScalesBuffer) gl.deleteBuffer(this.colorScalesBuffer);

		this.triVertexBuffer = createBuffer(gl, vertices);
		this.numVertices = vertices.length / 2;

		this.colorScalesBuffer = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, this.colorScalesBuffer);
		gl.bufferData(
			gl.ARRAY_BUFFER,
			new Float32Array(this.numVertices),
			gl.DYNAMIC_DRAW,
		);

		// before we run, draw mesh
		this.drawMesh();
	}

	start() {
		if (this.running) return;

		this.running = true;
		this.lastTime = 0;
		this.fpsTime = 0;
		this.fpsCounter = 0;
		this.animationId = requestAnimationFrame(this.runAnimation.bind(this));
	}

	stop() {
		if (!this.running) return;
		this.running = false;
		this.animationId = 0;
	}

	runAnimation(currentTime) {
		if (!this.running) return;

		const elapsed = (currentTime - this.lastTime) / 1000;
		this.lastTime = currentTime;

		const dt = Math.min(elapsed, 0.03);
		const result = this.wasmExports.runFrame(dt);
		const [ptr, length] = this.unpackPtrLength(result);
		const colorScales = new Float32Array(this.wasmBuffer, ptr, length);

		updateBuffer(this.gl, this.colorScalesBuffer, colorScales);
		this.renderTris();

		this.fpsTime += elapsed;
		this.fpsCounter++;

		if (this.fpsTime > 5) {
			postMessage({ type: "frameRate", value: this.fpsCounter / this.fpsTime });

			this.fpsTime = 0;
			this.fpsCounter = 0;

		}

		requestAnimationFrame(this.runAnimation.bind(this));
	}

	// private helpers
	unpackPtrLength(packed) {
		const ptr = Number(packed >> 32n);
		const length = Number(packed & 0xffffffffn);
		return [ptr, length];
	}

	refreshMemoryViews() {
		this.wasmBuffer = this.wasmInstance.exports.memory.buffer;
		const result = this.wasmExports.getSharedMemLoc();
		const [structPtr, structLength] = this.unpackPtrLength(result);

		this.structView = new DataView(this.wasmBuffer, structPtr, structLength);
	}

	// GRAPHICS STUFF
	drawMesh() {
		// should have been updated by setupViz
		const nx = this.structView.getInt32(0, true);
		const ny = this.structView.getInt32(4, true);
		const width = this.structView.getFloat32(8, true);
		const height = this.structView.getFloat32(12, true);

		const aspectRatio = width / height;
		this.canvas.height = this.canvas.width / aspectRatio;

		const result = this.wasmExports.getMeshRenderData(nx, ny, width, height);
		this.refreshMemoryViews();

		const [ptr, length] = this.unpackPtrLength(result);
		const vertices = new Float32Array(this.wasmBuffer, ptr, length);

		const gl = this.gl;

		const positionLocation = gl.getAttribLocation(
			this.lineProgram,
			"a_position",
		);
		const positionBuffer = createBuffer(gl, vertices);

		gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
		gl.clearColor(0, 0, 0, 0);
		gl.clear(gl.COLOR_BUFFER_BIT);

		gl.useProgram(this.lineProgram);

		gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
		gl.enableVertexAttribArray(positionLocation);
		gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

		const uniformColorLocation = gl.getUniformLocation(
			this.lineProgram,
			"u_color",
		);
		gl.uniform4f(uniformColorLocation, 0, 0, 0, 1);

		gl.drawArrays(gl.LINES, 0, vertices.length / 2);
	}

	renderTris() {
		const gl = this.gl;
		gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
		gl.clearColor(0, 0, 0, 0);
		gl.clear(gl.COLOR_BUFFER_BIT);

		gl.useProgram(this.triangleProgram);

		gl.bindBuffer(gl.ARRAY_BUFFER, this.triVertexBuffer);
		gl.enableVertexAttribArray(this.triVertexLocation);
		gl.vertexAttribPointer(this.triVertexLocation, 2, gl.FLOAT, false, 0, 0);

		gl.bindBuffer(gl.ARRAY_BUFFER, this.colorScalesBuffer);
		gl.enableVertexAttribArray(this.colorScaleLocation);
		gl.vertexAttribPointer(this.colorScaleLocation, 1, gl.FLOAT, false, 0, 0);

		gl.drawArrays(gl.TRIANGLES, 0, this.numVertices);
	}
}

const scenarioRendererPromise = new ScenarioRenderer().init();

// biome-ignore lint/suspicious/noGlobalAssign: onmessage is fine to set in a web worker
onmessage = async ({ data }) => {
	const scenarioRenderer = await scenarioRendererPromise;

	switch (data.type) {
		case "initCanvas":
			scenarioRenderer.setupWebGL(data.canvas);
			break;
		case "setup":
			scenarioRenderer.setup();
			break;
		case "start":
			scenarioRenderer.start();
			break;
		case "stop":
			scenarioRenderer.stop();
			break;
		default:
			console.error(`run-scenario cannot address type: ${data.type}`);
	}
};

// shaders

const triangleVertexShader = /* glsl */ `
	attribute vec2 a_position;
	attribute float colorScale;
	varying float v_colorScale;
	void main() {
		gl_Position = vec4(a_position, 0.0, 1.0);
		v_colorScale = colorScale;
	}
`;

const lineVertexShader = /* glsl */ `
	attribute vec4 a_position;
	
	void main() {
		gl_Position = a_position;
	}
`;

const triangleFragShader = /* glsl */ `
	precision mediump float;
	varying float v_colorScale;
	void main() {
		gl_FragColor = vec4(v_colorScale, 0.0, 1.0-v_colorScale, 1.0);
	}
`;

const lineFragShader = /* glsl */ `
	precision mediump float;
	uniform vec4 u_color;

	void main() {
		gl_FragColor = u_color;
	}
`;
