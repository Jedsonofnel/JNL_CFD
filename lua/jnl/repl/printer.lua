-- lua/jnl/repl/printer.lua - Terminal text printer with string formatters and builder API
-- <jed@nelson.ac> // 2026-05-26

local Printer = {}
Printer.__index = Printer

Printer._doc = "Terminal text printer with wrapping and indentation"

--
-- Static string formatters
--

local fmt = {}

function fmt.header(text, level)
	level = level or 1
	return "\n" .. string.rep("#", level) .. " " .. tostring(text) .. "\n"
end

function fmt.bullet(text)
	return "  - " .. tostring(text or "") .. "\n"
end

-- left-aligned key in a fixed column followed by value
function fmt.kv(key, value, opts)
	opts = opts or {}
	local w = opts.width or 16
	return string.format("  %-" .. w .. "s  %s\n",
		tostring(key or ""), tostring(value or ""))
end

function fmt.rule(opts)
	opts        = opts or {}
	local char  = opts.char or "-"
	local width = opts.width or 40
	return char:rep(width) .. "\n"
end

-- indent every line of a block by n spaces
function fmt.indent(text, n)
	local pad   = string.rep(" ", n or 2)
	local lines = {}
	for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = pad .. line
	end
	return table.concat(lines, "\n")
end

Printer.fmt = fmt

--
-- Builder
--

local function default_out(self)
	return function(s)
		self._buf[#self._buf + 1] = s
	end
end

function Printer.new(opts)
	opts = opts or {}
	local self = setmetatable({
		width = opts.width or 72,
		_buf  = {},
	}, Printer)
	self.out = opts.out or default_out(self)
	return self
end

-- _emit adds a trailing newline; for pre-formatted strings use self.out() directly
function Printer:_emit(line)
	self.out((line or "") .. "\n")
end

function Printer:line(text)
	self:_emit(text)
end

function Printer:blank()
	self:_emit("")
end

function Printer:header(text, level)
	self.out(fmt.header(text, level))
end

function Printer:bullet(text)
	self.out(fmt.bullet(text))
end

function Printer:kv(key, value, opts)
	self.out(fmt.kv(key, value, opts))
end

function Printer:rule(opts)
	self.out(fmt.rule(opts))
end

--
-- Wrapping helpers
--

local function split_long_word(word, width)
	local chunks = {}
	while #word > width do
		chunks[#chunks + 1] = word:sub(1, width)
		word = word:sub(width + 1)
	end
	if #word > 0 then chunks[#chunks + 1] = word end
	return chunks
end

function Printer:wrap(first_indent, rest_indent, text)
	first_indent = first_indent or ""
	rest_indent  = rest_indent or first_indent
	text         = tostring(text or "")

	if text == "" then
		self:_emit(first_indent)
		return
	end

	for para in (text .. "\n"):gmatch("(.-)\n") do
		if para:match("^%s*$") then
			self:_emit("")
		else
			self:_wrap_para(first_indent, rest_indent, para)
		end
		first_indent = rest_indent
	end
end

function Printer:_wrap_para(first_indent, rest_indent, para)
	local indent   = first_indent
	local line     = indent
	local has_word = false

	for word in para:gmatch("%S+") do
		local room  = math.max(1, self.width - #indent)
		local parts = #word > room and split_long_word(word, room) or { word }

		for _, part in ipairs(parts) do
			local sep = has_word and " " or ""
			if #line + #sep + #part <= self.width then
				line     = line .. sep .. part
				has_word = true
			else
				self:_emit(line)
				indent   = rest_indent
				line     = indent .. part
				has_word = true
			end
		end
	end

	if has_word then self:_emit(line) else self:_emit(first_indent) end
end

function Printer:columns(left, right, opts)
	opts                = opts or {}

	local indent        = opts.indent or "   "
	local left_width    = opts.left_width or 32
	local gap           = opts.gap or "  "
	local doc_indent    = opts.doc_indent or (indent .. "  ")

	left                = tostring(left or "")
	right               = tostring(right or "")

	local inline_prefix = string.format(
		"%s%-" .. tostring(left_width) .. "s%s",
		indent, left, gap)

	if #left <= left_width then
		local rest = string.rep(" ", #inline_prefix)
		self:wrap(inline_prefix, rest, right)
		return
	end

	self:wrap(indent, indent, left)
	if right ~= "" then
		self:wrap(doc_indent, doc_indent, right)
	end
end

function Printer:item(name, fields, opts)
	opts               = opts or {}

	local indent       = opts.indent or "   "
	local field_indent = opts.field_indent or (indent .. "  ")
	local label_width  = opts.label_width or 5

	self:wrap(indent, indent, tostring(name or ""))

	for _, field in ipairs(fields or {}) do
		local label = tostring(field[1] or "")
		local text  = tostring(field[2] or "")
		local first = string.format(
			"%s%-" .. tostring(label_width) .. "s ",
			field_indent, label .. ":")
		local rest  = string.rep(" ", #first)
		self:wrap(first, rest, text)
	end
end

function Printer:string()
	return table.concat(self._buf)
end

--
-- API
--

Printer._api = {
	new = {
		args = "opts:table?",
		ret  = "Printer",
		doc  = "Create a printer; opts: { width=72, out:fn? }; default out buffers to string()",
	},
}

Printer._types = {
	Printer = {
		kind        = "table",
		constructor = "Printer.new(opts?)",
		doc         = "Builder that accumulates formatted terminal output; all emit methods return nil",
		methods     = {
			-- structural
			header  = { args = "text:string, level:int?", ret = "nil", doc = "Emit a markdown heading (# = level 1); blank line before, none after" },
			bullet  = { args = "text:string", ret = "nil", doc = "Emit a single bullet item" },
			kv      = { args = "key:string, value:string, opts:table?", ret = "nil", doc = "Emit a key-value row; opts: { width=16 }" },
			rule    = { args = "opts:table?", ret = "nil", doc = "Emit a horizontal rule; opts: { char='-', width=40 }" },
			-- text
			line    = { args = "text:string?", ret = "nil", doc = "Emit one line" },
			blank   = { args = "", ret = "nil", doc = "Emit a blank line" },
			wrap    = { args = "first_indent, rest_indent, text:string", ret = "nil", doc = "Emit word-wrapped text with separate first/rest indentation" },
			columns = { args = "left, right:string, opts:table?", ret = "nil", doc = "Emit a two-column row; opts: { indent, left_width=32, gap, doc_indent }" },
			item    = { args = "name:string, fields:table, opts:table?", ret = "nil", doc = "Emit a named item with labelled sub-fields" },
			-- output
			string  = { args = "", ret = "string", doc = "Return buffered output; only valid with the default buffer sink" },
		},
	},
	["Printer.fmt"] = {
		kind        = "table",
		constructor = "Printer.fmt (static sub-table)",
		doc         = "Pure string formatters; return complete strings with newlines; safe to io.write() directly",
		methods     = {
			header = { args = "text:string, level:int?", ret = "string", doc = "Markdown heading; blank line before; level defaults to 1" },
			bullet = { args = "text:string", ret = "string", doc = "Single bullet item: '  - text'" },
			kv     = { args = "key, value:string, opts:table?", ret = "string", doc = "Key-value row; opts: { width=16 }" },
			rule   = { args = "opts:table?", ret = "string", doc = "Horizontal rule; opts: { char='-', width=40 }" },
			indent = { args = "text:string, n:int?", ret = "string", doc = "Indent every line of a block by n spaces (default 2)" },
		},
	},
}

return Printer
