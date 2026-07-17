-- lua/jnl/repl/printer.lua - Markdown-like terminal text printer
-- <jed@nelson.ac> // 2026-06-11

--- Format wrapped, Markdown-like text for terminals and generated documents.
local M = {}

--- A buffered or callback-backed terminal text printer.
---@class Printer
---@field width integer Maximum output width.
---@field out fun(text: string) Output callback.
---@field buffer string[] Buffered chunks used by `string`.
local Printer = {}
Printer.__index = Printer

--
-- Static string formatters
--

M.fmt = {}

local function clamp_heading_level(level)
    level = math.floor(tonumber(level) or 1)

    if level < 1 then
        return 1
    end
    if level > 6 then
        return 6
    end

    return level
end

--- Return a Markdown-style heading with surrounding whitespace.
---@param text any Heading text.
---@param level? integer Heading level from 1 to 6.
---@return string text
function M.fmt.header(text, level)
    level = clamp_heading_level(level)

    return string.format(
        "\n%s %s\n\n",
        string.rep("#", level),
        tostring(text or "")
    )
end

--- Return a Markdown-style bullet.
---@param text any Bullet text.
---@param opts? table Formatting options, including `indent`.
---@return string text
function M.fmt.bullet(text, opts)
    opts = opts or {}

    return string.format("%s- %s\n", opts.indent or "", tostring(text or ""))
end

--- Return a simple key-value line.
---@param key any Key or label.
---@param value any Value text.
---@param opts? table Formatting options, including `indent` and `separator`.
---@return string text
function M.fmt.kv(key, value, opts)
    opts = opts or {}

    return string.format(
        "%s%s%s%s\n",
        opts.indent or "",
        tostring(key or ""),
        opts.separator or ": ",
        tostring(value or "")
    )
end

--- Return a Markdown horizontal rule.
---@param opts? table Formatting options, including `indent`.
---@return string text
function M.fmt.rule(opts)
    opts = opts or {}

    return (opts.indent or "") .. "---\n\n"
end

--- Indent every line of a text block.
---@param text any Text to indent.
---@param count? integer Number of spaces; defaults to 2.
---@return string text
function M.fmt.indent(text, count)
    local pad = string.rep(" ", count or 2)
    local lines = {}

    text = tostring(text or "")

    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = pad .. line
    end

    return table.concat(lines, "\n")
end

--
-- Construction
--

local function default_out(printer)
    return function(text)
        printer.buffer[#printer.buffer + 1] = text
    end
end

--- Create a buffered or callback-backed printer.
---@param opts? table Options containing `width` and optional `out`.
---@return Printer printer
function M.new(opts)
    opts = opts or {}

    local printer = setmetatable({
        width = opts.width or 80,
        buffer = {},
    }, Printer)

    printer.out = opts.out or default_out(printer)

    return printer
end

--
-- Basic output
--

local function emit_line(printer, text)
    printer.out((text or "") .. "\n")
end

--- Emit one line.
---@param text? any Line content.
function Printer:line(text)
    emit_line(self, tostring(text or ""))
end

--- Emit one blank line.
function Printer:blank()
    emit_line(self, "")
end

--- Emit a Markdown-style heading.
---@param text any Heading text.
---@param level? integer Heading level from 1 to 6.
function Printer:header(text, level)
    self.out(M.fmt.header(text, level))
end

--- Emit a Markdown-style bullet.
---@param text any Bullet text.
---@param opts? table Formatting options.
function Printer:bullet(text, opts)
    self.out(M.fmt.bullet(text, opts))
end

--- Emit a key-value line.
---@param key any Key or label.
---@param value any Value text.
---@param opts? table Formatting options.
function Printer:kv(key, value, opts)
    self.out(M.fmt.kv(key, value, opts))
end

--- Emit a Markdown horizontal rule.
---@param opts? table Formatting options.
function Printer:rule(opts)
    self.out(M.fmt.rule(opts))
end

--
-- Wrapping
--

local function split_long_word(word, width)
    local chunks = {}

    while #word > width do
        chunks[#chunks + 1] = word:sub(1, width)
        word = word:sub(width + 1)
    end

    if word ~= "" then
        chunks[#chunks + 1] = word
    end

    return chunks
end

--- Emit wrapped text with separate first-line and continuation indents.
---@param first_indent? string First-line indentation or prefix.
---@param rest_indent? string Continuation indentation.
---@param text? any Text to wrap.
function Printer:wrap(first_indent, rest_indent, text)
    first_indent = first_indent or ""
    rest_indent = rest_indent or first_indent
    text = tostring(text or "")

    if text == "" then
        emit_line(self, first_indent)
        return
    end

    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        if paragraph:match("^%s*$") then
            emit_line(self, "")
        else
            self:wrap_paragraph(first_indent, rest_indent, paragraph)
        end

        first_indent = rest_indent
    end
end

--- Emit one wrapped paragraph.
---@private
---@param first_indent string First-line indentation or prefix.
---@param rest_indent string Continuation indentation.
---@param paragraph string Paragraph text.
function Printer:wrap_paragraph(first_indent, rest_indent, paragraph)
    local indent = first_indent
    local line = indent
    local has_word = false

    for word in paragraph:gmatch("%S+") do
        local room = math.max(1, self.width - #indent)
        local parts

        if #word > room then
            parts = split_long_word(word, room)
        else
            parts = { word }
        end

        for _, part in ipairs(parts) do
            local separator = has_word and " " or ""

            if #line + #separator + #part <= self.width then
                line = line .. separator .. part
                has_word = true
            else
                emit_line(self, line)

                indent = rest_indent
                line = indent .. part
                has_word = true
            end
        end
    end

    if has_word then
        emit_line(self, line)
    else
        emit_line(self, first_indent)
    end
end

--
-- Structured output
--

--- Emit a responsive two-column row.
---
--- The row is rendered inline when enough room remains for the right column.
--- Otherwise the left and right values are stacked.
---@param left any Left-hand label.
---@param right any Right-hand description.
---@param opts? table Column layout options.
function Printer:columns(left, right, opts)
    opts = opts or {}

    local indent = opts.indent or "  "
    local gap = opts.gap or "  "
    local left_width = opts.left_width or 24
    local min_right_width = opts.min_right_width or 28
    local doc_indent = opts.doc_indent or (indent .. "  ")

    left = tostring(left or "")
    right = tostring(right or "")

    local prefix_width = #indent + left_width + #gap
    local right_width = self.width - prefix_width

    local can_render_inline = not opts.stack
        and #left <= left_width
        and right_width >= min_right_width

    if can_render_inline then
        local first =
            string.format("%s%-" .. left_width .. "s%s", indent, left, gap)

        local rest = string.rep(" ", #first)

        self:wrap(first, rest, right)
        return
    end

    self:wrap(indent, indent, left)

    if right ~= "" then
        self:wrap(doc_indent, doc_indent, right)
    end
end

--- Emit a named item followed by labelled fields.
---@param name any Item name.
---@param fields table[] Fields represented as `{ label, text }`.
---@param opts? table Item layout options.
function Printer:item(name, fields, opts)
    opts = opts or {}

    local indent = opts.indent or "  "
    local field_indent = opts.field_indent or (indent .. "  ")
    local label_width = opts.label_width or 8

    self:wrap(indent .. "- ", indent .. "  ", tostring(name or ""))

    for _, field in ipairs(fields or {}) do
        local label = tostring(field[1] or "") .. ":"
        local text = tostring(field[2] or "")

        local first =
            string.format("%s%-" .. label_width .. "s ", field_indent, label)

        local rest = string.rep(" ", #first)

        self:wrap(first, rest, text)
    end
end

--
-- Buffered output
--

--- Return all output accumulated by the default buffered sink.
---@return string text
function Printer:string()
    return table.concat(self.buffer)
end

return M
