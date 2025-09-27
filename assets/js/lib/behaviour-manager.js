class BehaviourManager {
	constructor() {
		this.behaviours = new Map();
		this.contexts = new Map();
		this.observer = null;
	}

	register(selector, BehaviourClass) {
		this.behaviours.set(selector, BehaviourClass);
	}

	registerContext(selector, ContextClass) {
		this.contexts.set(selector, ContextClass);
	}

	async init() {
		await this.initContexts(document);
		this.applyBehaviours(document);
		this.startObserving();
	}

	async initContexts(root) {
		for (const [selector, ContextClass] of this.contexts) {
			const elements = root.querySelectorAll(selector);
			for (const el of elements) {
				if (!el._contextInstance) {
					const context = new ContextClass(el);
					await context.isReady; // Wait for whatever ready() does
					el._contextInstance = context;
					el._hasContext = true;
				}
			}
		}
	}

	applyBehaviours(root) {
		this.behaviours.forEach((BehaviourClass, selector) => {
			const elements = root.querySelectorAll(selector);
			elements.forEach((el) => {
				if (!el._appliedBehaviours) {
					el._appliedBehaviours = new Set();
				}

				const behaviourKey = BehaviourClass.name;
				if (!el._appliedBehaviours.has(behaviourKey)) {
					new BehaviourClass(el);
					el._appliedBehaviours.add(behaviourKey);
				}
			});
		});
	}

	startObserving() {
		// Watch for mutations (HTMX, dynamic content)
		this.observer = new MutationObserver((mutations) => {
			mutations.forEach((mutation) => {
				mutation.addedNodes.forEach((node) => {
					if (node.nodeType === Node.ELEMENT_NODE) {
						this.applyBehaviours(node);
					}
				});
			});
		});

		this.observer.observe(document.body, {
			childList: true,
			subtree: true,
		});
	}
}

export { BehaviourManager };
