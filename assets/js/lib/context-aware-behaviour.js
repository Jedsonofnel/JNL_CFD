export class ContextAwareBehaviour {
	constructor(element, contextClass) {
		this.element = element;
		this.context = contextClass.findContext(element);
		this.subscriptions = [];
	}

	subscribe(callback, selector) {
		const unsubscribe = this.context.subscribe(callback, selector);
		this.subscriptions.push(unsubscribe);
		return unsubscribe;
	}

	destroy() {
		this.subscriptions.forEach((unsub) => unsub());
		this.subscriptions = [];
	}
}
