import { ReactiveContext } from "../lib/reactive-context.js";

export class WorkbookContext extends ReactiveContext {
	constructor(element) {
		super(element, {
			sourceeCode: "",
			intepretationResults: null,
			isInterpreting: false,
		});

		this.wasmInstance = null

		// creating actions
		this.actions = this.createActions({
			updateSourceCode: (state, code) => ({
				sourceCode: code,
				interpretationResults:
					code !== state.sourceCode ? null : state.interpretationResults,
			}),
		});
	}

	async ready() {
		this.wasmInstance = await this.initWasm();
		return true
	}

	async initWasm() {
		await import("/assets/wasm/wasm_exec.js");

		const go = new Go();
		const wasmInstance = await WebAssembly.instantiateStreaming(
			fetch("/assets/wasm/cfd-latest.wasm"),
			go.importObject,
		);
		go.run(wasmInstance.instance);
		return wasmInstance.instance
	}

	// Helper to find the context from child elements
	static findContext(element) {
		let parent = element;
		while (parent) {
			if (
				parent._hasContext &&
				parent._contextInstance instanceof WorkbookContext
			) {
				return parent._contextInstance;
			}
			parent = parent.parentElement;
		}
		throw new Error("WorkbookContext not found");
	}
}
