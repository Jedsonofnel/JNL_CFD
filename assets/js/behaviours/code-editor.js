import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class CodeEditorBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);

		this.removeLeadingWhitespace()
	}

	removeLeadingWhitespace() {
		this.element.textContent = this.element.textContent.trim()
	}
}
