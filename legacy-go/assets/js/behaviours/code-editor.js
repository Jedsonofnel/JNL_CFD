import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class CodeEditorBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);

		this.removeLeadingWhitespace();

		this.parserWorker = new Worker(
			new URL("../workers/parse-workbook.js", import.meta.url),
			{ type: "module" },
		);
		this.setupWorker();

		this.setupWatcher();

		this.parse();
	}

	parse() {
		this.parserWorker.postMessage(this.element.textContent);
	}

	removeLeadingWhitespace() {
		this.element.textContent = this.element.textContent.trim();
	}

	setupWatcher() {
		this.context.state.documentSrc = this.element.textContent

		this.element.addEventListener("input", () => {
			this.context.state.documentSrc = this.element.textContent;
		});
	}

	setupWorker() {
		this.parserWorker.onmessage = ({ data }) => {
			console.log(data);
		};

		this.parserWorker.onerror = (error) => {
			console.error("Parser worker error: ", error.message);
		};
	}
}

function debounce(func, timeout = 200) {
	let timer;
	return (...args) => {
		clearTimeout(timer);
		timer = setTimeout(() => {
			func.apply(this, args);
		}, timeout);
	};
}
