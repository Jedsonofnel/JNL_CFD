const wasmReadyPromise = (async () => {
	await import("/assets/wasm/wasm_exec.js");

	const go = new Go();
	const wasmInstance = await WebAssembly.instantiateStreaming(
		fetch("/assets/wasm/cfd-latest.wasm"),
		go.importObject,
	);
	go.run(wasmInstance.instance);
	return wasmInstance;
})();

let isRunning = false;
let animationId = null;
let lastTime = 0;

let fpsTime = 0.0;
let fpsCounter = 0;

let wasmInstance = null;

// biome-ignore lint/suspicious/noGlobalAssign: onmessage is fine to set in a web worker
onmessage = async ({ data }) => {
	wasmInstance = await wasmReadyPromise;

	switch (data.type) {
		case "reset":
			reset(data.params);
			break;
		case "start":
			start();
			break;
		case "stop":
			stop();
			break;
		default:
			console.error(`run-scenario cannot address type: ${data.type}`);
	}
};

function start() {
	if (isRunning) return;

	isRunning = true;

	function animationLoop(currentTime) {
		if (!isRunning) return;

		const elapsed = (currentTime - lastTime) / 1000;
		lastTime = currentTime;

		const targetDt = 1.0 / 60;
		const dt = Math.min(elapsed, targetDt * 2);

		const start = performance.now();

		runFrame(dt, "temperature");
		const resultsPtr = getResultsPtr();
		const resultsLength = getResultsLength();

		// const wasmMemory = new Float32Array(
		// 	wasmInstance.instance.exports.memory.buffer,
		// 	resultsPtr,
		// 	resultsLength,
		// );

		// console.log(`WASM took: ${wasmTime}ms`);

		// postMessage({
		// 	type: "frame",
		// 	colourScales: Array.from(wasmMemory),
		// });

		fpsTime += elapsed;
		fpsCounter++;

		if (fpsTime > 5) {
			postMessage({
				type: "frameRate",
				value: fpsCounter / fpsTime,
			});

			fpsTime = 0.0;
			fpsCounter = 0;
		}

		animationId = requestAnimationFrame(animationLoop);
	}

	animationId = requestAnimationFrame(animationLoop);
}

function stop() {
	isRunning = false;
	lastTime = 0;
	if (animationId) {
		cancelAnimationFrame(animationId);
		animationId = null;
	}
}

function reset(params) {
	const res = setupScenarioViz(params.diffusivity);

	postMessage(
		{
			type: "geometry",
			vertices: res.vertices,
			metadata: {
				width: res.width,
				height: res.height,
			},
		},
		[res.vertices.buffer],
	);
}
