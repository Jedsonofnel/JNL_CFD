export class EDNParser {
	constructor(edn) {
		this.edn = edn;
		this.pos = 0;
	}

	parse() {
		this.skipWhitespace();
		return this.parseValue();
	}

	skipWhitespace() {
		while (this.pos < this.edn.length) {
			const ch = this.edn[this.pos];
			if (ch === ";") {
				// Skip comment to end of line
				while (this.pos < this.edn.length && this.edn[this.pos] !== "\n") {
					this.pos++;
				}
			} else if (/[\s,]/.test(ch)) {
				this.pos++;
			} else {
				break;
			}
		}
	}

	peek() {
		this.skipWhitespace();
		return this.edn[this.pos];
	}

	consume() {
		return this.edn[this.pos++];
	}

	parseValue() {
		this.skipWhitespace();
		const ch = this.peek();

		if (ch === '"') return this.parseString();
		if (ch === "[") return this.parseVector();
		if (ch === "{") return this.parseMap();
		if (ch === "(") return this.parseList();
		if (ch === "#") return this.parseSet();
		if (ch === ":") return this.parseKeyword();
		if (ch === "t" || ch === "f") return this.parseBoolean();
		if (ch === "n") return this.parseNil();
		if (/[-+0-9]/.test(ch)) return this.parseNumber();

		throw new Error(`Unexpected character: ${ch} at position ${this.pos}`);
	}

	parseString() {
		this.consume(); // opening "
		let str = "";
		while (this.pos < this.edn.length) {
			const ch = this.consume();
			if (ch === "\\") {
				const next = this.consume();
				const escapes = { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\" };
				str += escapes[next] || next;
			} else if (ch === '"') {
				return str;
			} else {
				str += ch;
			}
		}
		throw new Error("Unterminated string");
	}

	parseNumber() {
		let num = "";
		while (
			this.pos < this.edn.length &&
			/[-+0-9.eE]/.test(this.edn[this.pos])
		) {
			num += this.consume();
		}
		return parseFloat(num);
	}

	parseKeyword() {
		this.consume(); // :
		let kw = "";
		while (
			this.pos < this.edn.length &&
			/[^,\s[\]{}()"';]/.test(this.edn[this.pos])
		) {
			kw += this.consume();
		}
		return Symbol.for(`:${kw}`);
	}

	parseBoolean() {
		if (this.edn.substring(this.pos, this.pos + 4) === "true") {
			this.pos += 4;
			return true;
		}
		if (this.edn.substring(this.pos, this.pos + 5) === "false") {
			this.pos += 5;
			return false;
		}
		throw new Error("Invalid boolean");
	}

	parseNil() {
		if (this.edn.substring(this.pos, this.pos + 3) === "nil") {
			this.pos += 3;
			return null;
		}
		throw new Error("Invalid nil");
	}

	parseVector() {
		this.consume(); // [
		const arr = [];
		while (this.peek() !== "]") {
			arr.push(this.parseValue());
		}
		this.consume(); // ]
		return arr;
	}

	parseList() {
		this.consume(); // (
		const arr = [];
		while (this.peek() !== ")") {
			arr.push(this.parseValue());
		}
		this.consume(); // )
		return arr; // treating lists as arrays
	}

	parseMap() {
		this.consume(); // {
		const obj = {};
		while (this.peek() !== "}") {
			const key = this.parseValue();
			const val = this.parseValue();
			// Convert keyword symbols to strings for object keys
			const keyStr = typeof key === "symbol" ? key.description.slice(1) : key;
			obj[keyStr] = val;
		}
		this.consume(); // }
		return obj;
	}

	parseSet() {
		this.consume(); // #
		if (this.consume() !== "{") throw new Error("Expected { after #");
		const items = [];
		while (this.peek() !== "}") {
			items.push(this.parseValue());
		}
		this.consume(); // }
		return new Set(items);
	}
}

// Usage:
// const data = new EDNParser(ednString).parse();
