import { BehaviourManager } from "./lib/behaviour-manager.js";
import { MeshPeek } from "./mesh-peek.js";
import { PeeksList } from "./peeks-list.js";

const manager = new BehaviourManager();
manager.register("peeks-list", PeeksList);
manager.register("mesh-peek", MeshPeek);

document.addEventListener("DOMContentLoaded", () => manager.init());
