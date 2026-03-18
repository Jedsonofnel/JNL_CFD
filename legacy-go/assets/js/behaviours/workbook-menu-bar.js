import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class WorkbookMenuBarBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);
		this.element = element;

		this.runBtn = element.querySelector(`[data-menu-bar="run-btn"]`);
		this.splitBtn = element.querySelector(`[data-menu-bar="split-btn"]`);
		this.resultsBtn = element.querySelector(`[data-menu-bar="results-btn"]`);
		this.editorBtn = element.querySelector(`[data-menu-bar="editor-btn"]`);

		this.interpIndicator = element.querySelector(
			`[data-menu-bar="interpreter-indicator"]`,
		);
		this.setupIndicator();

		this.setupBtns();
		this.setupSubscriptions();
		this.setupHeightVar();
	}

	setupIndicator() {
		this.context.events.addEventListener("interpreter:start", () => {
			this.interpIndicator.textContent = "Running...";
			this.interpIndicator.classList.remove(
				"menu-bar__interp-indicator--ready",
			);
		});

		this.context.events.addEventListener("interpreter:finish", () => {
			this.interpIndicator.textContent = "Ready";
			this.interpIndicator.classList.add("menu-bar__interp-indicator--ready");
		});

		this.context.events.addEventListener("interpreter:dirty", () => {
			this.interpIndicator.textContent = "Modified";
			this.interpIndicator.classList.remove(
				"menu-bar__interp-indicator--ready",
			);
		});
	}

	setupHeightVar() {
		this.setMenuHeight();
		window.addEventListener("resize", this.setMenuHeight.bind(this));
	}

	setMenuHeight() {
		const height = this.element.offsetHeight;
		this.context.element.style.setProperty("--menu-height", `${height}px`);
	}

	setupBtns() {
		this.runBtn.addEventListener("click", () => {
			this.context.events.dispatchEvent(new CustomEvent("interpreter:force"));
		});
		this.splitBtn.addEventListener("click", () => {
			this.context.state.layout = "split";
		});
		this.resultsBtn.addEventListener("click", () => {
			this.context.state.layout = "results";
		});
		this.editorBtn.addEventListener("click", () => {
			this.context.state.layout = "editor";
		});
	}

	updateLayoutBtns(layout) {
		switch (layout) {
			case "editor":
				this.splitBtn.disabled = false;
				this.editorBtn.disabled = true;
				this.resultsBtn.disabled = false;
				break;
			case "results":
				this.splitBtn.disabled = false;
				this.editorBtn.disabled = false;
				this.resultsBtn.disabled = true;
				break;
			case "split":
				this.splitBtn.disabled = true;
				this.editorBtn.disabled = false;
				this.resultsBtn.disabled = false;
				break;
		}
	}

	setupSubscriptions() {
		this.updateLayoutBtns(this.context.state.layout);

		this.subscribe(
			({ value }) => this.updateLayoutBtns(value),
			({ prop }) => prop === "layout",
		);
	}
}
