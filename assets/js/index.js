import { WorkbookLayoutBehaviour } from "./behaviours/workbook-layout.js";
import { WorkbookContext } from "./contexts/workbook.js";
import { BehaviourManager } from "./lib/behaviour-manager.js";
import { CodeEditorBehaviour } from "./behaviours/code-editor.js";

const manager = new BehaviourManager();

manager.registerContext(`[data-js-context="workbook"]`, WorkbookContext);

manager.register(
	`[data-js-behaviour*="workbook-layout"]`,
	WorkbookLayoutBehaviour,
);
manager.register(`[data-js-behaviour*="code-editor"]`, CodeEditorBehaviour)

document.addEventListener("DOMContentLoaded", async () => await manager.init());
