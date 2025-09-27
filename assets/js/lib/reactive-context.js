export class ReactiveContext {
	constructor(element, initialState = {}) {
		this.element = element;
		this.subscribers = new Set();

		this.state = new Proxy(initialState, {
			set: (target, prop, value) => {
				const oldValue = target[prop];
				target[prop] = value;

				this.subscribers.forEach((subscriber) => {
					if (subscriber.selector(this.state, prop, oldValue, value)) {
						subscriber.callback(this.state, { prop, oldValue, value });
					}
				});

				return true;
			},
		});

		// event bus
		this.events = new EventTarget();

		this.isReady = this.ready()
	}

	async ready() {
		return true
	}

	subscribe(callback, selector = () => true) {
		const subscriber = { callback, selector };
		this.subscribers.add(subscriber);

		// return unsub
		return () => this.subscribers.delete(subscriber);
	}

	createActions(actionMap) {
		const actions = {};
		Object.entries(actionMap).forEach(([name, actionFn]) => {
			actions[name] = (...args) => {
				const result = actionFn(this.state, ...args);

				// if it returns something, set the thing in state
				if (result && typeof result === "object") {
					Object.assign(this.state, result);
				}
			};
		});
		return actions;
	}
}
