class PeeksList {
	constructor(element) {
		this.root = element;
		this.init();
	}

	init() {
		const res = fetch("/api/up")
			.then((response) => response.json())
			.then((data) => console.log(data));
	}
}

export { PeeksList };
