class BehaviourManager {
	constructor() {
		this.behaviours = new Map();
		this.observer = null;
	}

	register(name, BehaviourClass) {
		this.behaviours.set(name, BehaviourClass);
	}

	init() {
		// Initial scan
		this.applyBehaviours(document);

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

	applyBehaviours(root) {
		this.behaviours.forEach((BehaviourClass, name) => {
			const elements = root.querySelectorAll(`[data-js-"${name}"]`);
			elements.forEach((el) => {
				if (!el._behaviourInstance) {
					el._behaviourInstance = new BehaviourClass(el);
				}
			});
		});
	}
}

export { BehaviourManager };
