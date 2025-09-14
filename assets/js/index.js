import { BehaviourManager } from "./lib/behaviour-manager.js";

const manager = new BehaviourManager();

document.addEventListener("DOMContentLoaded", () => manager.init());
console.log("HEY")
