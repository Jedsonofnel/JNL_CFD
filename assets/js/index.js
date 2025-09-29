import {
	CodeEditorBehaviour,
	CodeInterpreterBehaviour,
	WorkbookLayoutBehaviour,
	WorkbookMenuBarBehaviour,
	WorkbookResultsTableBehaviour,
} from "./behaviours/index.js";

import { WorkbookContext } from "./contexts/workbook.js";
import { BehaviourManager } from "./lib/behaviour-manager.js";

const manager = new BehaviourManager();

// REGISTER CONTEXTS

manager.registerContext(`[data-context="workbook"]`, WorkbookContext);

// REGISTER BEHAVIOURS

manager.register(
	`[data-behaviour*="workbook-layout"]`,
	WorkbookLayoutBehaviour,
);

manager.register(
	`[data-behaviour*="workbook-menu-bar"]`,
	WorkbookMenuBarBehaviour,
);

manager.register(`[data-behaviour*="code-editor"]`, CodeEditorBehaviour);

manager.register(
	`[data-behaviour*="code-interpreter"]`,
	CodeInterpreterBehaviour,
);

manager.register(
	`[data-behaviour*="results-table"]`,
	WorkbookResultsTableBehaviour,
);

// INIT BEHAVIOURS

document.addEventListener("DOMContentLoaded", () => manager.init());
