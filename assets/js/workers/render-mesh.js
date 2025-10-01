import { createBuffer, createShaderProgram } from "../lib/webgl-helper.js";

class MeshRenderer {
	constructor() {
		this.wasmInstance = null;
		this.readyPromise = this.init();
	}

	loadMesh(documentSrc, meshSym) {
		const textBytes = new TextEncoder().encode(documentSrc);
		this.textBuffer.set(textBytes);
		this.wasmInstance.exports.evalText(textBytes.length);

		const symBytes = new TextEncoder().encode(meshSym);
		this.textBuffer.set(symBytes);
		const result = this.wasmInstance.exports.loadMesh(symBytes.length);
		if (result !== 0) {
			throw new Error("Error loading mesh");
		}
	}

	setupCanvas(canvas) {
		const aspectRatio = this.wasmInstance.exports.getMeshAspectRatio();
		canvas.height = canvas.width / aspectRatio;

		const gl = canvas.getContext("webgl2") || canvas.getContext("webgl");
		gl.viewport(0, 0, canvas.width, canvas.height);

		return gl;
	}

	renderMesh(canvas) {
		const gl = this.setupCanvas(canvas);

		const packed = this.wasmInstance.exports.getMeshLineVertices();
		const [vPtr, vLen] = unpackPtrLength(packed);
		const vertBuf = new Float32Array(
			this.wasmInstance.exports.memory.buffer,
			vPtr,
			vLen,
		);

		const program = createShaderProgram(gl, vertexShader, fragShader);
		const positionLocation = gl.getAttribLocation(program, "a_position");
		const positionBuffer = createBuffer(gl, vertBuf);

		gl.useProgram(program);

		gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
		gl.enableVertexAttribArray(positionLocation);
		gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

		const uniformColorLocation = gl.getUniformLocation(program, "u_color");
		gl.uniform4f(uniformColorLocation, 0, 0, 0, 1);
		gl.drawArrays(gl.LINES, 0, vertBuf.length / 2);
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

const meshRenderer = new MeshRenderer();
meshRenderer.init();

self.onmessage = async ({ data }) => {
	await meshRenderer.ready();

	const { meshSym, canvas, documentSrc } = data;

	if (!meshSym || !canvas || !documentSrc) {
		throw new Error(
			"missing an arg from meshSym, canvas and documentSrc to mesh renderer",
		);
	}

	// populate the environment and load the mesh
	meshRenderer.loadMesh(documentSrc, meshSym);

	// then render it
	meshRenderer.renderMesh(canvas);
};

// SHADER CODE

const vertexShader = /* glsl */ `
	attribute vec4 a_position;
	
	void main() {
		gl_Position = a_position;
	}
`;

const fragShader = /* glsl */ `
	precision mediump float;
	uniform vec4 u_color;

	void main() {
		gl_FragColor = u_color;
	}
`;
