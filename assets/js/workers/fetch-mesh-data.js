await import("/assets/wasm/wasm_exec.js");

const go = new Go();
const wasmInstance = await WebAssembly.instantiateStreaming(
	fetch("/assets/wasm/cfd-latest.wasm"),
	go.importObject,
);
go.run(wasmInstance.instance);

const meshData = getMeshData();

postMessage(
	{
		vertices: meshData,
	},
	[meshData.buffer],
);

close();
