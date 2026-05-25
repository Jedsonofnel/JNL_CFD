-- lua/jnl/term_printer.lua

local Printer = {}
Printer.__index = Printer

Printer._doc = "Terminal text printer with wrapping and indentation"

local function default_out(self)
	return function(s)
		self._buf[#self._buf + 1] = s
	end
end

function Printer.new(opts)
	opts = opts or {}

	local self = setmetatable({
		width = opts.width or 72,
		_buf = {},
	}, Printer)

	self.out = opts.out or default_out(self)
	return self
end

function Printer:_emit(line)
	line = line or ""
	self.out(line .. "\n")
end

function Printer:line(line)
	self:_emit(line or "")
end

function Printer:blank()
	self:_emit("")
end

local function split_long_word(word, width)
	local chunks = {}

	while #word > width do
		chunks[#chunks + 1] = word:sub(1, width)
		word = word:sub(width + 1)
	end

	if #word > 0 then
		chunks[#chunks + 1] = word
	end

	return chunks
end

function Printer:wrap(first_indent, rest_indent, text)
	first_indent = first_indent or ""
	rest_indent = rest_indent or first_indent
	text = tostring(text or "")

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
	local indent = first_indent
	local line = indent
	local has_word = false

	for word in para:gmatch("%S+") do
		local room = math.max(1, self.width - #indent)
		local parts = #word > room and split_long_word(word, room) or { word }

		for _, part in ipairs(parts) do
			local sep = has_word and " " or ""

			if #line + #sep + #part <= self.width then
				line = line .. sep .. part
				has_word = true
			else
				self:_emit(line)
				indent = rest_indent
				line = indent .. part
				has_word = true
			end
		end
	end

	if has_word then
		self:_emit(line)
	else
		self:_emit(first_indent)
	end
end

function Printer:columns(left, right, opts)
	opts = opts or {}

	local indent = opts.indent or "   "
	local left_width = opts.left_width or 32
	local gap = opts.gap or "  "
	local doc_indent = opts.doc_indent or (indent .. "  ")

	left = tostring(left or "")
	right = tostring(right or "")

	local inline_prefix = string.format(
		"%s%-" .. tostring(left_width) .. "s%s",
		indent,
		left,
		gap
	)

	-- If the left column fits in its reserved space, use the compact
	-- two-column layout:
	--
	--   name(args)                 doc starts here and wraps here
	--
	if #left <= left_width then
		local rest = string.rep(" ", #inline_prefix)
		self:wrap(inline_prefix, rest, right)
		return
	end

	-- If the signature is too long, avoid creating a ridiculous continuation
	-- indent that leaves only a few characters for the doc.
	--
	--   VeryLongSignature(args...) -> ret
	--     doc starts here with a sane hanging indent
	--
	self:wrap(indent, indent, left)

	if right ~= "" then
		self:wrap(doc_indent, doc_indent, right)
	end
end

function Printer:item(name, fields, opts)
	opts = opts or {}

	local indent = opts.indent or "   "
	local field_indent = opts.field_indent or (indent .. "  ")
	local label_width = opts.label_width or 5

	self:wrap(indent, indent, tostring(name or ""))

	for _, field in ipairs(fields or {}) do
		local label = tostring(field[1] or "")
		local text = tostring(field[2] or "")

		local first = string.format(
			"%s%-" .. tostring(label_width) .. "s ",
			field_indent,
			label .. ":"
		)

		local rest = string.rep(" ", #first)
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
		ret = "Printer",
		doc = "Create a terminal printer",
	},
}

Printer._types = {
	Printer = {
		kind = "table",
		constructor = "jnl.term_printer.new",
		doc = "Printer object for wrapped terminal output",
		methods = {
			line = {
				args = "text:string?",
				ret = "nil",
				doc = "Print one line",
			},
			blank = {
				args = "",
				ret = "nil",
				doc = "Print a blank line",
			},
			wrap = {
				args = "first_indent:string, rest_indent:string, text:string",
				ret = "nil",
				doc = "Print wrapped text with separate first/rest indentation",
			},
			columns = {
				args = "left:string, right:string, opts:table?",
				ret = "nil",
				doc = "Print a wrapped two-column row",
			},
			string = {
				args = "",
				ret = "string",
				doc = "Return collected output when using the default buffer sink",
			},
		},
	},
}

return Printer
