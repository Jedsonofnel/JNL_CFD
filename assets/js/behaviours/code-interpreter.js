import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class CodeInterpreterBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);

		this.context.events.addEventListener(
			"interpreter:force",
			this.interpret.bind(this),
		);

		this.debouncedInterpreter = debounce(this.interpret.bind(this));
		this.element.addEventListener("input", () => {
			this.context.events.dispatchEvent(new CustomEvent("interpreter:dirty"));
			this.debouncedInterpreter();
		});

		this.interpreterWorker = new Worker(
			new URL("../workers/interpret-workbook.js", import.meta.url),
			{ type: "module" },
		);
		this.setupWorker();

		this.interpret();
	}

	interpret() {
		this.interpreterWorker.postMessage(this.element.textContent);
		this.context.events.dispatchEvent(new CustomEvent("intepreter:start"));
	}

	setupWorker() {
		this.interpreterWorker.onmessage = ({ data }) => {
			this.context.state.interpreterResults = data;
			this.context.events.dispatchEvent(new CustomEvent("interpreter:finish"));
		};

		this.interpreterWorker.onerror = (error) => {
			console.error("Interpreter worker error: ", error.message);
		};
	}
}

function debounce(func, timeout = 1000) {
	let timer;
	return (...args) => {
		clearTimeout(timer);
		timer = setTimeout(() => {
			func.apply(this, args);
		}, timeout);
	};
}
