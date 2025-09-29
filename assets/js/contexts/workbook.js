import { ReactiveContext } from "../lib/reactive-context.js";

export class WorkbookContext extends ReactiveContext {
	constructor(element) {
		super(element, {
			layout: "editor",
			interpreterResults: [],
		});

		// creating actions
		this.actions = this.setActions();
	}

	setActions() {
		return this.createActions({
			updateLayout: (_, layout) => {
				if (["editor", "results", "split"].includes(layout)) {
					return { layout: layout };
				}
			},
		});
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
