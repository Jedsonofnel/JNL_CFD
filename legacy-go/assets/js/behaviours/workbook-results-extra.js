import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class WorkbookResultsExtraBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);

		this.variant = element.getAttribute("data-workbook-results-extra");
		if (!["mesh-viz", "scenario-viz"].includes(this.variant)) {
			throw new Error(
				`WorkbookResultsExtra needs a correct attribute, not ${this.variant}`,
			);
		}

		this.symbol = element.getAttribute("data-workbook-results-extra-symbol");
		if (!this.symbol) {
			throw new Error(
				`WorkbookResultsExtra expects to be passed [data-workbook-results-extra-symbol]`,
			);
		}

		this.resultsPane = this.context.element.querySelector(
			`[data-workbook="results-pane"]`,
		);

		if (!this.resultsPane) {
			throw new Error(
				`WorkbookResultsExtra expects to find a [data-workbook="results-pane"]`,
			);
		}

		this.element.addEventListener("click", this.createViewport.bind(this));
	}

	createViewport() {
		// should remomve existing
		this.context.events.dispatchEvent(new CustomEvent("viz:clear"));

		const canvas = document.createElement("canvas");
		canvas.setAttribute("width", "800");
		canvas.setAttribute("height", "0");
		canvas.classList.add("viz-canvas");

		const container = document.createElement("div");
		container.setAttribute("data-viz-behaviour", this.variant);
		container.setAttribute("data-viz-symbol", this.symbol);
		container.classList.add("viz-container");

		const title =
			this.variant === "mesh-viz"
				? "Mesh Visualisation"
				: "Scenario Visualisation";

		const buttons =
			this.variant === "mesh-viz"
				? `<button data-viz-btn="close">Close</button>`
				: `<button data-viz-btn="start">Start</button>
					<button data-viz-btn="stop">Stop</button>
					<button data-viz-btn="close">Close</button>`;

		const menuHTML = `<div class="workbook-menu workbook-menu--thin">
			<h2 class="thin">${title}</h2>
			<div class="menu-bar__push-right"></div>
			${buttons}
		</div>`;

		container.appendChild(canvas);
		container.insertAdjacentHTML("afterBegin", menuHTML);

		this.resultsPane.prepend(container);
	}
}
