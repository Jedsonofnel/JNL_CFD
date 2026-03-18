import {
	createBuffer,
	createShaderProgram,
	updateBuffer,
} from "../lib/webgl-helper.js";

class ScenarioRenderer {
	constructor() {
		this.wasmInstance = null;
		this.readyPromise = this.init();

		this.setupFinished = false;
		this.running = false;
		this.lastTime = 0;
		this.animationId;
	}

	// SETUP CODE

	setup(data) {
		const { scenarioSym, canvas, documentSrc } = data;

		if (!scenarioSym || !canvas || !documentSrc) {
			throw new Error(
				"missing an arg from scenarioSym, canvas and documentSrc to scenario renderer",
			);
		}

		// LOAD SCENARIO

		this.loadScenario(documentSrc, scenarioSym);
		const gl = this.setupCanvas(canvas);
		this.gl = gl;

		// SETTING UP WEBGL

		this.program = createShaderProgram(gl, vertexShader, fragShader);
		this.triLoc = gl.getAttribLocation(this.program, "a_position");
		this.colorScaleLoc = gl.getAttribLocation(this.program, "colorScale");

		const packed = this.wasmInstance.exports.getMeshTriVertices();
		const [ptr, length] = unpackPtrLength(packed);
		const vertices = new Float32Array(
			this.wasmInstance.exports.memory.buffer,
			ptr,
			length,
		);

		this.triVertexBuf = createBuffer(gl, vertices);
		const numVs = vertices.length / 2;
		this.numVertices = numVs;

		this.colorScalesBuf = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, this.colorScalesBuf);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(numVs), gl.DYNAMIC_DRAW);

		this.setupFinished = true;
		this.start();
	}

	loadScenario(documentSrc, scenarioSym) {
		const textBytes = new TextEncoder().encode(documentSrc);
		this.textBuffer.set(textBytes);
		this.wasmInstance.exports.evalText(textBytes.length);

		const symBytes = new TextEncoder().encode(scenarioSym);
		this.textBuffer.set(symBytes);
		const result = this.wasmInstance.exports.loadScenario(symBytes.length);

		if (result !== 0) {
			throw new Error("Error loading scenario");
		}
	}

	setupCanvas(canvas) {
		const aspectRatio = this.wasmInstance.exports.getMeshAspectRatio();
		canvas.height = canvas.width / aspectRatio;

		const gl = canvas.getContext("webgl2") || canvas.getContext("webgl");
		gl.viewport(0, 0, canvas.width, canvas.height);

		return gl;
	}

	// START/STOP CODE

	start() {
		if (this.running || !this.setupFinished) return;

		this.running = true;
		this.lastTime = 0;
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
		const result = this.wasmInstance.exports.runFrame(dt);
		const [ptr, length] = unpackPtrLength(result);
		const colorScales = new Float32Array(
			this.wasmInstance.exports.memory.buffer,
			ptr,
			length,
		);

		updateBuffer(this.gl, this.colorScalesBuf, colorScales);
		this.renderTris();

		requestAnimationFrame(this.runAnimation.bind(this));
	}

	renderTris() {
		const gl = this.gl;
		gl.useProgram(this.program);

		gl.bindBuffer(gl.ARRAY_BUFFER, this.triVertexBuf);
		gl.enableVertexAttribArray(this.triLoc);
		gl.vertexAttribPointer(this.triLoc, 2, gl.FLOAT, false, 0, 0);

		gl.bindBuffer(gl.ARRAY_BUFFER, this.colorScalesBuf);
		gl.enableVertexAttribArray(this.colorScaleLoc);
		gl.vertexAttribPointer(this.colorScaleLoc, 1, gl.FLOAT, false, 0, 0);

		gl.drawArrays(gl.TRIANGLES, 0, this.numVertices);
	}

	async init() {
		await import("/assets/wasm/wasm_exec.js");

		const go = new Go();
		const wasmInstance = await WebAssembly.instantiateStreaming(
			fetch("/assets/wasm/cfd-latest.wasm"),
			go.importObject,
		);

		await go.run(wasmInstance.instance);
		this.wasmInstance = wasmInstance.instance;
	}

	get textBuffer() {
		const packed = this.wasmInstance.exports.getTextView();
		const [textPtr, textLen] = unpackPtrLength(packed);
		const textBuf = new Uint8Array(
			this.wasmInstance.exports.memory.buffer,
			textPtr,
			textLen,
		);
		return textBuf;
	}

	async ready() {
		await this.readyPromise;
	}
}

function unpackPtrLength(packed) {
	const ptr = Number(packed >> 32n);
	const length = Number(packed & 0xffffffffn);
	return [ptr, length];
}

const scenarioRenderer = new ScenarioRenderer();

self.onmessage = async ({ data }) => {
	await scenarioRenderer.ready();

	switch (data.type) {
		case "setup":
			scenarioRenderer.setup(data);
			postMessage({ type: "started" });
			break;
		case "start":
			scenarioRenderer.start();
			postMessage({ type: "started" });
			break;
		case "stop":
			postMessage({ type: "stopped" });
			scenarioRenderer.stop();
			break;
	}
};

// SHADER CODE

const vertexShader = /* glsl */ `
	attribute vec2 a_position;
	attribute float colorScale;
	varying float v_colorScale;
	void main() {
		gl_Position = vec4(a_position, 0.0, 1.0);
		v_colorScale = colorScale;
	}
`;

const fragShader = /* glsl */ `
	precision mediump float;
	varying float v_colorScale;
	void main() {
		gl_FragColor = vec4(v_colorScale, 0.0, 1.0 - v_colorScale, 1.0);
	}
`;
