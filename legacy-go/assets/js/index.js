import { Visualiser } from "./behaviours/index.js";
import { BehaviourManager } from "./lib/behaviour-manager.js";

const manager = new BehaviourManager();

//
// REGISTER BEHAVIOURS
//

manager.register(`[data-behaviour*="visualiser"]`, Visualiser);

//
// INIT BEHAVIOURS
//

document.addEventListener("DOMContentLoaded", () => manager.init());

document.body.addEventListener("htmx:afterSwap", (event) => {
	manager.init(event.detail.target);
});
