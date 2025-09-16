import { PeekAPI } from "./lib/peek-api.js";

export class PeeksList {
	constructor(element) {
		this.container = element;
		this.peeks = [];
		this.api = new PeekAPI("/api/peeks");

		this.unsubscribe = this.api.onUpdate((peeks) => {
			this.handleNewPeeks(peeks);
		});

		this.init();
	}

	init() {
		this.render();
		this.api.startPolling();
	}

	handleNewPeeks(peeks) {
		this.peeks = peeks;
		this.render();
	}

	render() {
		const html = this.peeks
			.map(
				(peek) => `
			<li>View peek: ${peek.type}, <a href="/peeks/123">here</a></li>
		`,
			)
			.join("\n");

		this.container.innerHTML = html;
	}
}
