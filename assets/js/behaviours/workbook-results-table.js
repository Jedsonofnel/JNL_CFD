import { WorkbookContext } from "../contexts/workbook.js";
import { ContextAwareBehaviour } from "../lib/context-aware-behaviour.js";

export class WorkbookResultsTableBehaviour extends ContextAwareBehaviour {
	constructor(element) {
		super(element, WorkbookContext);

		this.table = element.querySelector('[data-results-table="table"]')
		this.tableBody = element.querySelector('[data-results-table="table-body"]')
		this.renderTable(this.context.state.interpreterResults);
		this.setupSubscriptions();
	}

	renderTable(results) {
		const tableEntries = []
		console.log(results)
		for (const [index, result] of results.entries()) {
			const resultType = result.result ? result.result.type : "ERROR"
			const resultValue = this.parseResultValue(result)
			tableEntries.push(`
				<tr>
					<td class="td--right">${index+1}</td>
					<td class="td--center">${result.startPos.line}:${result.endPos.line}</td>
					<td>${escapeHTML(resultType)}</td>
					<td>${escapeHTML(resultValue)}</td>
				</tr>
			`)
		}

		this.tableBody.innerHTML = tableEntries.join("\n")
	}

	parseResultValue(result) {
		if (result.result) {
			return result.result.repr
		}

		const errorMsgs = []
		for (const error of result.errors) {
			errorMsgs.push(error.message)
		}

		return errorMsgs.join(", ")
	}

	setupSubscriptions() {
		this.subscribe(
			({ value }) => this.renderTable(value),
			({ prop }) => prop === "interpreterResults",
		);
	}
}

function escapeHTML(text) {
	const div = document.createElement("div");
	div.textContent = text;
	return div.innerHTML;
}
