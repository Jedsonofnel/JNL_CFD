import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class WorkbookLayoutBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);
		this.root = element

		// important elements
		this.codePane = element.querySelector(`[data-js-workbook="editor-pane"]`)
		this.resultsPane = element.querySelector(`[data-js-workbook="results-pane"]`)
		this.resultsBtn = element.querySelector(`[data-js-workbook-layout="results-btn"]`)
		this.editorBtn = element.querySelector(`[data-js-workbook-layout="editor-btn"]`)

		this.layout = "editor" // or "results" or "split"


		this.setupBtns()
		this.renderLayout()
	}

	setupBtns() {
		this.resultsBtn.addEventListener("click", () => {
			if (this.layout != "results") {
				this.layout = "results"
				this.resultsBtn.disabled = true
				this.editorBtn.disabled = false
				this.renderLayout()
			}
		})
		this.editorBtn.addEventListener("click", () => {
			if (this.layout != "editor") {
				this.layout = "editor"
				this.editorBtn.disabled = true
				this.resultsBtn.disabled = false
				this.renderLayout()
			}
		})
	}

	renderLayout() {
		switch(this.layout) {
			case "editor":
				this.codePane.hidden = false
				this.resultsPane.hidden = true
				break;
			case "results":
				this.codePane.hidden = true
				this.resultsPane.hidden = false
				break;
			case "split":
				break;
			default:
				throw new Error("bad layout value")
		}
	}
}
