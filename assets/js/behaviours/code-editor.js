import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class CodeEditorBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);
		this.root = element

		this.removeLeadingWhitespace()
	}

	removeLeadingWhitespace() {
		this.root.textContent = this.root.textContent.trim()
	}
}
