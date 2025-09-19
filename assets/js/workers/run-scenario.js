// helper class used by onmessage at the bottom
class ScenarioRenderer {
	constructor(canvas) {
		// webgl setup
		this.canvas = canvas;

		// animation data
		this.running = false;
		this.lastTime = 0;
		this.animationId = 0;
		this.fpsTime = 0;
		this.fpsCounter = 0;

		// wasm memory management
		this.wasmInstance = null;
		this.wasmExports = null;
		this.wasmMemory = null;
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
		this.refreshMemoryViews();

		return this;
	}

	setup() {
		console.log(this.wasmInstance);
		console.log(this.wasmExports);

		const result = this.wasmExports.setupScenarioViz(0.0001);
		const [verticesPtr, verticesLength] = this.unpackPtrLength(result);

		const vertices = new Float32Array(
			this.wasmMemory.buffer,
			verticesPtr,
			verticesLength,
		);

		this.refreshMemoryViews();
		const sceneWidth = this.structView.getFloat32(8, true);
		const sceneHeight = this.structView.getFloat32(12, true);
		console.log(`scene dims: ${sceneWidth}, ${sceneHeight}`);
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
		const [colorsPtr, colorsLength] = this.unpackPtrLength(result);

		this.fpsTime += elapsed;
		this.fpsCounter++;

		if (this.fpsTime > 5) {
			console.log(`FPS: ${this.fpsCounter / this.fpsTime}`);
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
		this.wasmMemory = this.wasmInstance.exports.memory;
		const result = this.wasmExports.getSharedMemLoc();
		const [structPtr, structLength] = this.unpackPtrLength(result);

		this.structView = new DataView(
			this.wasmMemory.buffer,
			structPtr,
			structLength,
		);
	}
}

const scenarioRendererPromise = new ScenarioRenderer().init();

// biome-ignore lint/suspicious/noGlobalAssign: onmessage is fine to set in a web worker
onmessage = async ({ data }) => {
	const scenarioRenderer = await scenarioRendererPromise;

	switch (data.type) {
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
