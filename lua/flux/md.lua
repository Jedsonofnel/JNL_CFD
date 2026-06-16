-- lua/flux/md.lua - Minimal Markdown + YAML front matter parser.
-- <jed@nelson.ac> // 2026-06-16
--
-- Scope:
--   Front matter : flat key-value scalars + simple lists (--- delimited)
--   Blocks       : ATX headings, paragraphs, fenced code, ul, ol,
--                  blockquotes, thematic breaks
--   Inline       : code spans, **bold**, __bold__, *italic*, links, HTML escaping
--   Out of scope : inline HTML, tables, setext headings, reference-style links
--
-- API:
--   md.parse(src)        -> { html, meta, toc }
--   md.render(src)       -> html string only
--   md.parse_file(path)  -> { html, meta, toc }

local M = {}

--
-- Utilities
--

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function slugify(s)
	return s:lower()
		:gsub("[^%w%s%-]", "")
		:gsub("%s+", "-")
		:gsub("%-+", "-")
		:gsub("^%-*(.-)%-*$", "%1")
end

--
-- YAML front matter
--

local function coerce(s)
	s = trim(s)
	if s == "true" then return true end
	if s == "false" then return false end

	local n = tonumber(s)
	if n then return n end
	return s:match('^"(.*)"$') or s:match("^'(.*)'$") or s
end

-- Strip and parse front matter delimited by --- lines.
-- Only flat key-value scalars and simple scalar lists are supported.
local function parse_front_matter(src)
	local meta = {}
	local fm, rest = src:match("^%-%-%-\n(.-)\n%-%-%-\n?(.*)")
	if not fm then return meta, src end

	local cur_key, cur_list
	for line in (fm .. "\n"):gmatch("([^\n]*)\n") do
		local key, val = line:match("^(%w[%w_%-]*):%s*(.*)$")
		if key then
			if cur_list then meta[cur_key] = cur_list end
			cur_key, cur_list = key, nil
			val = trim(val)
			if val == "" then
				cur_list = {}
			else
				meta[key] = coerce(val)
			end
		else
			local item = line:match("^%s*%-%s+(.-)%s*$")
			if item and cur_list then
				cur_list[#cur_list + 1] = coerce(item)
			end
		end
	end
	if cur_list then meta[cur_key] = cur_list end

	return meta, rest or ""
end

--
-- Inline Rendering
--

local function escape(s)
	return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

-- Apply inline markup to a plain-text string.
-- Order: escape HTML entities → protect code spans → bold → italic → links
-- → restore code spans.
-- Note: underscore-italic (_..._) is intentionally omitted to avoid false
-- positives on snake_case identifiers in prose. Use *italic* instead.
local function inline(s)
	s = escape(s)

	local stash = {}
	s = s:gsub("`([^`]+)`", function(c)
		stash[#stash + 1] = "<code>" .. c .. "</code>"
		return "\0" .. #stash .. "\0"
	end)

	s = s:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
		:gsub("__(.-)__", "<strong>%1</strong>")
	s = s:gsub("%*(.-)%*", "<em>%1</em>")

	-- link with optional title: [text](url "title")
	s = s:gsub('%[(.-)%]%(([^ "%)]+)%s+"([^"]*)"%)', '<a href="%2" title="%3">%1</a>')
	-- plain link: [text](url)
	s = s:gsub('%[(.-)%]%(([^%)]+)%)', '<a href="%2">%1</a>')

	s = s:gsub("\0(%d+)\0", function(n) return stash[tonumber(n)] end)

	return s
end

--
-- Block classification
--

local function is_blank(s) return s:match("^%s*$") ~= nil end

local function is_heading(s)
	local hashes = s:match("^(#+)%s")
	return hashes ~= nil and #hashes <= 6
end

local function is_fence(s) return s:match("^```") ~= nil end
local function is_bq(s) return s:match("^>") ~= nil end
local function is_ul(s) return s:match("^%s*[-*+]%s") ~= nil end
local function is_ol(s) return s:match("^%s*%d+%.%s") ~= nil end

local function is_break(s)
	return s:match("^%-%-%-+%s*$") ~= nil
		or s:match("^%*%*%*+%s*$") ~= nil
		or s:match("^___+%s*$") ~= nil
end

-- True for anything that should terminate a paragraph mid-scan.
local function is_block_start(s)
	return is_blank(s) or is_heading(s) or is_fence(s)
		or is_break(s) or is_bq(s) or is_ul(s) or is_ol(s)
end

--
-- Block parsing
--

local function parse_blocks(lines)
	local blocks = {}
	local i = 1

	local function peek() return lines[i] end
	local function take()
		local l = lines[i]; i = i + 1; return l
	end

	while i <= #lines do
		local line = peek()

		if is_blank(line) then
			take()
		elseif is_fence(line) then
			local lang = take():match("^```%s*(%S*)")
			local body = {}
			while i <= #lines and not peek():match("^```%s*$") do
				body[#body + 1] = take()
			end
			if i <= #lines then take() end
			blocks[#blocks + 1] = { type = "code", lang = lang or "", text = table.concat(body, "\n") }
		elseif is_heading(line) then
			take()
			local hashes, text = line:match("^(#+)%s+(.*)")
			text = trim(text:gsub("%s+#+%s*$", ""))
			blocks[#blocks + 1] = { type = "heading", level = #hashes, text = text, id = slugify(text) }
		elseif is_break(line) then
			take()
			blocks[#blocks + 1] = { type = "hr" }
		elseif is_bq(line) then
			local blines = {}
			while i <= #lines and is_bq(peek()) do
				blines[#blines + 1] = take():gsub("^>%s?", "")
			end
			blocks[#blocks + 1] = { type = "blockquote", lines = blines }
		elseif is_ul(line) then
			local items = {}
			while i <= #lines and (is_ul(peek()) or (peek():match("^  %S") and #items > 0)) do
				local l = take()
				local indent, text = l:match("^(%s*)[-*+]%s+(.*)")
				if indent then
					items[#items + 1] = { depth = #indent, text = trim(text) }
				end
			end
			blocks[#blocks + 1] = { type = "ul", items = items }
		elseif is_ol(line) then
			local items = {}
			while i <= #lines and (is_ol(peek()) or (peek():match("^  %S") and #items > 0)) do
				local l = take()
				local indent, text = l:match("^(%s*)%d+%.%s+(.*)")
				if indent then
					items[#items + 1] = { depth = #indent, text = trim(text) }
				end
			end
			blocks[#blocks + 1] = { type = "ol", items = items }
		else
			local plines = {}
			while i <= #lines and not is_block_start(peek()) do
				plines[#plines + 1] = take()
			end
			if #plines > 0 then
				blocks[#blocks + 1] = { type = "para", text = table.concat(plines, " ") }
			end
		end
	end

	return blocks
end

--
-- List rendering
--

-- Renders items at depth 0 as top-level <li>; consecutive depth > 0 items
-- are collected into a nested <ul>/<ol> inside the preceding top-level <li>.
local function render_items(items, tag)
	local out = {}
	local i = 1
	while i <= #items do
		local item = items[i]
		i = i + 1
		local inner = inline(item.text)
		if i <= #items and items[i].depth > 0 then
			local sub = {}
			while i <= #items and items[i].depth > 0 do
				sub[#sub + 1] = "<li>" .. inline(items[i].text) .. "</li>"
				i = i + 1
			end
			inner = inner .. "<" .. tag .. ">" .. table.concat(sub) .. "</" .. tag .. ">"
		end
		out[#out + 1] = "<li>" .. inner .. "</li>"
	end
	return table.concat(out)
end

--
-- Block rendering
--

local render_blocks -- forward declaration for blockquote recursion

render_blocks = function(blocks)
	local parts = {}
	local toc   = {}

	for _, b in ipairs(blocks) do
		if b.type == "heading" then
			toc[#toc + 1] = { level = b.level, id = b.id, text = b.text }
			parts[#parts + 1] = string.format(
				'<h%d id="%s">%s</h%d>', b.level, b.id, inline(b.text), b.level)
		elseif b.type == "para" then
			parts[#parts + 1] = "<p>" .. inline(b.text) .. "</p>"
		elseif b.type == "code" then
			local cls = b.lang ~= "" and (' class="language-' .. b.lang .. '"') or ""
			parts[#parts + 1] = "<pre><code" .. cls .. ">" .. escape(b.text) .. "</code></pre>"
		elseif b.type == "hr" then
			parts[#parts + 1] = "<hr />"
		elseif b.type == "blockquote" then
			local inner, inner_toc = render_blocks(parse_blocks(b.lines))
			for _, e in ipairs(inner_toc) do toc[#toc + 1] = e end
			parts[#parts + 1] = "<blockquote>" .. inner .. "</blockquote>"
		elseif b.type == "ul" then
			parts[#parts + 1] = "<ul>" .. render_items(b.items, "ul") .. "</ul>"
		elseif b.type == "ol" then
			parts[#parts + 1] = "<ol>" .. render_items(b.items, "ol") .. "</ol>"
		end
	end

	return table.concat(parts, "\n"), toc
end

--
-- Public API
--

--- Parse a Markdown source string with optional YAML front matter.
---@param src string
---@return { html: string, meta: table, toc: table }
function M.parse(src)
	src = src:gsub("\r\n", "\n"):gsub("\r", "\n")
	local meta, body = parse_front_matter(src)
	local lines = {}
	for line in (body .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end
	local html, toc = render_blocks(parse_blocks(lines))
	return { meta = meta, html = html, toc = toc }
end

--- Render Markdown to an HTML string, discarding front matter and toc.
---@param src string
---@return string
function M.render(src)
	return M.parse(src).html
end

--- Parse a Markdown file from disk.
---@param path string
---@return { html: string, meta: table, toc: table }
function M.parse_file(path)
	local f = assert(io.open(path, "r"))
	local src = f:read("*a")
	f:close()
	return M.parse(src)
end

--- Extract the first h1 from a parsed doc, returning it separately from the rest.
--- If no h1 is present, title is nil and html is unchanged.
---
---   local doc   = md.parse(src)
---   local split = md.split_h1(doc)
---   -- split.title   : string|nil   plain text of the first h1
---   -- split.html    : string       remaining HTML with h1 stripped
---   -- split.toc     : table        toc entries with h1 entry removed
---   -- split.meta    : table        unchanged
---@param doc { html: string, meta: table, toc: table }
---@return { title: string|nil, html: string, meta: table, toc: table }
function M.split_h1(doc)
	local title   = nil
	local toc     = {}

	-- Strip the first <h1 ...>...</h1> from the rendered HTML.
	local html    = doc.html:gsub('<h1[^>]*>(.-)</h1>\n?', function(inner)
		if not title then
			title = inner:gsub("<[^>]+>", "")
			return ""
		end
		return '<h1>' .. inner .. '</h1>'
	end, 1)

	-- Mirror the toc without the first h1 entry.
	local skipped = false
	for _, entry in ipairs(doc.toc) do
		if not skipped and entry.level == 1 then
			skipped = true
		else
			toc[#toc + 1] = entry
		end
	end

	return { title = title, html = html, meta = doc.meta, toc = toc }
end

return M
