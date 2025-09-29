import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class WorkbookLayoutBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);
		this.root = element;

		// important elements
		this.codePane = element.querySelector(`[data-workbook="editor-pane"]`);
		this.resultsPane = element.querySelector(`[data-workbook="results-pane"]`);

		this.context.state.layout = "split"; // starting layout
		this.renderLayout("split");
		this.setupSubscriptions();
	}

	renderLayout(layout) {
		switch (layout) {
			case "editor":
				this.codePane.hidden = false;
				this.resultsPane.hidden = true;
				this.element.classList.add("layout--editor")
				this.element.classList.remove("layout--results")
				this.element.classList.remove("layout--split")
				break;
			case "results":
				this.codePane.hidden = true;
				this.resultsPane.hidden = false;
				this.element.classList.remove("layout--editor")
				this.element.classList.add("layout--results")
				this.element.classList.remove("layout--split")
				break;
			case "split":
				this.codePane.hidden = false;
				this.resultsPane.hidden = false;
				this.element.classList.remove("layout--editor")
				this.element.classList.remove("layout--results")
				this.element.classList.add("layout--split")
				break;
		}
	}

	setupSubscriptions() {
		this.subscribe(
			({ value }) => this.renderLayout(value),
			({ prop }) => prop === "layout",
		);
	}
}
