const wasmReadyPromise = (async () => {
	await import("/assets/wasm/wasm_exec.js");

	const go = new Go();
	const wasmInstance = await WebAssembly.instantiateStreaming(
		fetch("/assets/wasm/cfd-latest.wasm"),
		go.importObject,
	);
	go.run(wasmInstance.instance);
	return wasmInstance.instance;
})();

self.onmessage = async ({ data }) => {
	const wasmInstance = await wasmReadyPromise;

	const packed = wasmInstance.exports.getTextView();
	const [textPtr, textLen] = unpackPtrLength(packed);
	const textBuf = new Uint8Array(
		wasmInstance.exports.memory.buffer,
		textPtr,
		textLen,
	);

	const textBytes = new TextEncoder().encode(data);
	textBuf.set(textBytes);

	// the crucial difference from interpret - we just call parseText
	const result = wasmInstance.exports.parseText(textBytes.length);
	const [resPtr, resLen] = unpackPtrLength(result);
	const resultBuf = new Uint8Array(
		wasmInstance.exports.memory.buffer,
		resPtr,
		resLen,
	);

	const jsonString = new TextDecoder().decode(resultBuf);
	const jsonData = JSON.parse(jsonString);

	// TODO: figure the rest of this out
	// console.log(jsonData);
};

function unpackPtrLength(packed) {
	const ptr = Number(packed >> 32n);
	const length = Number(packed & 0xffffffffn);
	return [ptr, length];
}
