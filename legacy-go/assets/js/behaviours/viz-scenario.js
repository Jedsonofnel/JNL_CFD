import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class ScenarioViz extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);

		const canvas = element.querySelector("canvas").transferControlToOffscreen();
		this.documentSrc = this.context.state.documentSrc;

		this.symbol = element.getAttribute("data-viz-symbol");
		if (!this.symbol) {
			throw new Error(`ScenarioViz expects to be passed [data-viz-symbol]`);
		}

		this.handleDestroy = this.destroy.bind(this);

		this.rendererWorker = new Worker(
			new URL("../workers/render-scenario.js", import.meta.url),
			{ type: "module" },
		);
		this.setupWorker(canvas);

		this.setupButtons();

		this.context.events.addEventListener("viz:clear", this.handleDestroy);
	}

	setupButtons() {
		const closeBtn = this.element.querySelector(`[data-viz-btn="close"]`);
		closeBtn.addEventListener("click", this.handleDestroy);

		this.startBtn = this.element.querySelector(`[data-viz-btn="start"]`);
		this.startBtn.addEventListener("click", () => {
			this.rendererWorker.postMessage({ type: "start" });
		});

		this.stopBtn = this.element.querySelector(`[data-viz-btn="stop"]`);
		this.stopBtn.addEventListener("click", () => {
			this.rendererWorker.postMessage({ type: "stop" });
		});

		// both start disabled
		this.startBtn.disabled = true;
		this.stopBtn.disabled = true;
	}

	setupWorker(canvas) {
		this.rendererWorker.onmessage = ({ data }) => {
			switch (data.type) {
				case "started":
					this.startBtn.disabled = true;
					this.stopBtn.disabled = false;
					break;
				case "stopped":
					this.startBtn.disabled = false;
					this.stopBtn.disabled = true;
					break;
			}
		};

		this.rendererWorker.onerror = (error) => {
			console.error(`scenario renderer error ${error.message}`);
		};

		this.rendererWorker.postMessage(
			{
				type: "setup",
				scenarioSym: this.symbol,
				canvas: canvas,
				documentSrc: this.documentSrc,
			},
			[canvas],
		);
	}

	destroy() {
		if (this.rendererWorker) {
			this.rendererWorker.terminate();
			this.rendererWorker = null;
		}

		// Remove event listeners
		const closeBtn = this.element.querySelector(`[data-viz-btn="close"]`);
		if (closeBtn) {
			closeBtn.removeEventListener("click", this.handleDestroy);
		}

		// Remove context event listener
		this.context.events.removeEventListener("viz:clear", this.handleDestroy);

		// Remove the element from DOM
		this.element.remove();
	}
}
