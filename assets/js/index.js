import { BehaviourManager } from "./lib/behaviour-manager.js";
import { MeshViewport } from "./mesh-viewport.js";
import { ScenarioViewport } from "./scenario-viewport.js";

const manager = new BehaviourManager();
manager.register(`[data-js-viewport="mesh"]`, MeshViewport);
manager.register(`[data-js-viewport="scenario"]`, ScenarioViewport);

document.addEventListener("DOMContentLoaded", () => manager.init());
