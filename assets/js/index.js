import { BehaviourManager } from "./lib/behaviour-manager.js";
import { MeshViz } from "./mesh-viz.js";
import { ScenarioViz } from "./scenario-viz.js";

const manager = new BehaviourManager();
manager.register(`[data-js-viz="mesh"]`, MeshViz);
manager.register(`[data-js-viz="scenario"]`, ScenarioViz);

document.addEventListener("DOMContentLoaded", () => manager.init());
