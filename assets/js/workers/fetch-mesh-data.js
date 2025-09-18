const wasmReadyPromise = (async () => {
	await import("/assets/wasm/wasm_exec.js");

	const go = new Go();
	const wasmInstance = await WebAssembly.instantiateStreaming(
		fetch("/assets/wasm/cfd-latest.wasm"),
		go.importObject,
	);
	go.run(wasmInstance.instance);
})();

// biome-ignore lint/suspicious/noGlobalAssign: onmessage is fine to set in a web worker
onmessage = async ({data}) => {
	const {nx, ny, width, height, type} = data
	if (type !== "structuredMeshDefinition") {
		console.error("must be a structured mesh definition")
	}

	await wasmReadyPromise;
	const meshData = getMeshData(nx, ny, width, height);
	postMessage({ vertices: meshData }, [meshData.buffer]);
};
