export class PeekAPI {
	constructor(url = "/api/peeks") {
		this.url = url;
		this.polling = false;
		this.callbacks = new Set();
	}

	onUpdate(callback) {
		this.callbacks.add(callback);
		return () => this.callbacks.delete(callback);
	}

	startPolling(interval = 5000) {
		if (this.polling) return;
		this.polling = true;
		this.poll(interval);
	}

	stopPolling() {
		this.polling = false;
	}

	// TODO get proper long polling working
	async poll(_) {
		const url = this.url;
		fetch(url)
			.then((response) => response.json())
			.then((peeks) => {
				if (peeks.length > 0) {
					this.notifyCallbacks(peeks);
				}
			})
			.catch((error) => console.error(error));
	}

	notifyCallbacks(peeks) {
		for (const cb of this.callbacks) {
			try {
				cb(peeks);
			} catch (error) {
				console.error("Callback error: ", error);
			}
		}
	}
}
