import { BehaviourManager } from "./lib/behaviour-manager.js";
import { PeeksList } from "./peeks-list.js";

const manager = new BehaviourManager();
manager.register("peeks-list", PeeksList);

document.addEventListener("DOMContentLoaded", () => manager.init());
