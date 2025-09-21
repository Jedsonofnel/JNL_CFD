export class ScenarioViewport {
	constructor(element) {
		this.container = element;
		this.dataFieldset = element.querySelector("[data-js-viewport-data]");

		this.gl = null;
		this.program = null;
		this.positionBuffer = null;
		this.colourBuffer = null;
		this.positionLocation = null;
		this.colourLocation = null;
		this.numVertices = 0;

		this.scenarioWorker = new Worker(
			new URL("./workers/run-scenario.js", import.meta.url),
			{ type: "module" },
		);

		const canvas = element.querySelector("[data-js-viewport-canvas]");
		const offscreenCanvas = canvas.transferControlToOffscreen();
		this.scenarioWorker.postMessage(
			{
				type: "initCanvas",
				canvas: offscreenCanvas,
			},
			[offscreenCanvas],
		);

		this.scenarioWorker.onmessage = ({ data }) => {
			switch (data.type) {
				case "frameRate":
					console.log(`FPS: ${data.value}`);
					break;
				default:
					console.error(
						"main thread cannot respond to message type: ",
						data.type,
					);
			}
		};

		this.scenarioWorker.onerror = (error) => {
			console.error("worker error: ", error.message);
		};

		this.registerButtons();
		this.setupViz();
	}

	registerButtons() {
		this.startButton = this.container.querySelector(
			`[data-js-viewport-button="start"]`,
		);
		this.startButton.addEventListener("click", this.startViz.bind(this));

		this.stopButton = this.container.querySelector(
			`[data-js-viewport-button="stop"]`,
		);
		this.stopButton.addEventListener("click", this.stopViz.bind(this));

		this.resetButton = this.container.querySelector(
			`[data-js-viewport-button="reset"]`,
		);
		this.resetButton.addEventListener("click", this.setupViz.bind(this));
	}

	setupViz() {
		if (!this.dataFieldset) return null;

		const inputs = Array.from(this.dataFieldset.querySelectorAll("input"));

		const scenarioParams = Object.fromEntries(
			inputs.map((input) => [
				input.name,
				input.type === "number" ? parseFloat(input.value) : input.value,
			]),
		);

		this.scenarioWorker.postMessage({
			type: "setup",
			params: scenarioParams,
		});

		this.startButton.disabled = false;
		this.stopButton.disabled = true;
		this.resetButton.disabled = false;
	}

	startViz() {
		this.scenarioWorker.postMessage({ type: "start" });

		this.startButton.disabled = true;
		this.stopButton.disabled = false;
		this.resetButton.disabled = true;
	}

	stopViz() {
		this.scenarioWorker.postMessage({ type: "stop" });
		this.startButton.disabled = false;
		this.stopButton.disabled = true;
		this.resetButton.disabled = false;
	}
}
