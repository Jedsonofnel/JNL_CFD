-- lua/flux/router.lua - HTTP request router for the Flux web framework.
-- <jed@nelson.ac> // 2026-06-13

--- HTTP request router.
---
--- Routes are matched in registration order; the first match wins.
--- Path parameters use :name syntax and are captured into req.params:
---
---   r:get("/guide/:slug", function(req, res)
---     local slug = req.params.slug
---     res.html("<h1>" .. slug .. "</h1>")
---   end)
local M = {}

--
-- Pattern compilation
--

-- Compile a route path into a Lua pattern and an ordered list of param names.
local function compile(path)
	local params = {}
	local pat = path:gsub(":([%w_]+)", function(name)
		params[#params + 1] = name
		return "([^/]+)"
	end)
	return { pat = "^" .. pat .. "$", params = params }
end

--
-- Router
--

---@class FluxRouter
---@field routes table[]
local Router = {}
Router.__index = Router

--- Register a handler for a method and path pattern.
---
--- Returns self for chaining.
---@param method string HTTP method in upper case.
---@param path string Route path; use :name for captured segments.
---@param handler fun(req: table, res: table): boolean?
---@return FluxRouter self
function Router:on(method, path, handler)
	local c = compile(path)
	self.routes[#self.routes + 1] = {
		method  = method,
		pat     = c.pat,
		params  = c.params,
		handler = handler,
	}
	return self
end

--- Dispatch a request to the first matching registered route.
---
--- Populates req.params with path captures before calling the handler.
--- Returns the handler's return value on a match, or nil when no route matched.
---@param req table Request table with method and path fields.
---@param res table Response object.
---@return boolean? matched
function Router:dispatch(req, res)
	for _, route in ipairs(self.routes) do
		if route.method == req.method then
			local matches = { req.path:match(route.pat) }
			if #matches > 0 then
				req.params = {}
				for i, name in ipairs(route.params) do
					req.params[name] = matches[i]
				end
				return route.handler(req, res)
			end
		end
	end
end

--
-- Shorthand HTTP method
--

---@param path string Route path; use :name for captured segments.
---@param handler fun(req: table, res: table): boolean?
---@return FluxRouter self
function Router:get(path, handler)
	return self:on("GET", path, handler)
end

---@param path string Route path; use :name for captured segments.
---@param handler fun(req: table, res: table): boolean?
---@return FluxRouter self
function Router:post(path, handler)
	return self:on("POST", path, handler)
end

---@param path string Route path; use :name for captured segments.
---@param handler fun(req: table, res: table): boolean?
---@return FluxRouter self
function Router:put(path, handler)
	return self:on("PUT", path, handler)
end

---@param path string Route path; use :name for captured segments.
---@param handler fun(req: table, res: table): boolean?
---@return FluxRouter self
function Router:delete(path, handler)
	return self:on("DELETE", path, handler)
end

---@param path string Route path; use :name for captured segments.
---@param handler fun(req: table, res: table): boolean?
---@return FluxRouter self
function Router:patch(path, handler)
	return self:on("PATCH", path, handler)
end

--
-- File helpers
--

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close(); return true
	end
	return false
end

local function read_file(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Collapse path traversal and leading slashes from a URL-derived relative path.
local function sanitize(rel)
	return (rel:gsub("%.%.", ""):gsub("//+", "/"):gsub("^/+", ""))
end

-- Strip the last dot-extension from a relative path, if present.
-- "fvm/overview"    → "fvm/overview"
-- "fvm/overview.md" → "fvm/overview"
local function stem(rel)
	return rel:match("^(.+)%.[^/%.]+$") or rel
end

--
-- :static
--

--- Serve files from dir under URL prefix with no processing.
--- Replaces the static_root / static opts on flux.serve.
--- Multiple :static registrations are fine.
---@param prefix string URL prefix, e.g. "/assets"
---@param dir string Filesystem directory to serve from.
---@return FluxRouter self
function Router:static(prefix, dir)
	prefix = prefix:gsub("/$", "")
	local pat = "^" .. prefix .. "/(.*)$"
	self.routes[#self.routes + 1] = {
		method  = "GET",
		pat     = pat,
		params  = {},
		handler = function(req, res)
			local rel = sanitize(req.path:match(pat) or "")
			if rel == "" then
				res.not_found(); return
			end
			res.file(dir .. "/" .. rel)
		end,
	}
	return self
end

--
-- :mount
--

--- Mount a directory for dynamic doc serving.
---
--- Resolution order for a request to prefix/some/path:
---   1. dir/some/path.lua   → must return { content, meta?, toc? }
---   2. dir/some/path.md    → parsed with flux.md
---   3. dir/some/path.html  → content verbatim, empty meta/toc
---   4. dir/some/path/index (applying the same .lua/.md/.html order)
---   5. 404
---
--- Any recognised extension on the URL is stripped before resolution so
--- /docs/overview, /docs/overview.md, and /docs/overview.html all resolve
--- identically and in the same priority order.
---
--- If layout is provided it receives a page table on every hit:
---   { content: string, meta: table, toc: table }
--- and must return a complete HTML string.
--- Without layout, the raw content string is sent.
---
---@param prefix string URL prefix, e.g. "/docs"
---@param dir string Filesystem directory to mount.
---@param opts? { layout?: fun(page: table): string, index?: string }
---@return FluxRouter self
function Router:mount(prefix, dir, opts)
	opts         = opts or {}
	local layout = opts.layout
	local index  = opts.index or "index.md"
	local md     = require "flux.md" -- lazy: avoids load-order issues

	prefix       = prefix:gsub("/$", "")
	local pat    = "^" .. prefix .. "(.*)$"

	-- Try the three candidate extensions for one stem path.
	-- Returns a page table or nil.
	local function try_stem(s)
		if file_exists(s .. ".lua") then
			local chunk, err = loadfile(s .. ".lua")
			if not chunk then error("mount: error loading " .. s .. ".lua: " .. err) end
			local r = chunk()
			return { content = r.content or "", meta = r.meta or {}, toc = r.toc or {} }
		end
		if file_exists(s .. ".md") then
			local doc = md.parse_file(s .. ".md")
			return { content = doc.html, meta = doc.meta, toc = doc.toc }
		end
		if file_exists(s .. ".html") then
			return { content = read_file(s .. ".html"), meta = {}, toc = {} }
		end
		return nil
	end

	self.routes[#self.routes + 1] = {
		method  = "GET",
		pat     = pat,
		params  = {},
		handler = function(req, res)
			local rel = sanitize(req.path:match(pat) or "")

			-- bare prefix hit → serve index directly
			if rel == "" then
				local index_stem = dir .. "/" .. stem(index)
				local page = try_stem(index_stem)
					or (file_exists(dir .. "/" .. index) and try_stem(dir .. "/" .. stem(index)))
				if not page then
					res.not_found(); return
				end
				res.html(layout and layout(page) or page.content)
				return
			end

			local base = dir .. "/" .. stem(rel)

			-- 1-3: direct stem resolution
			local page = try_stem(base)

			-- 4: treat rel as a directory, try index inside it
			if not page then
				page = try_stem(base .. "/" .. stem(index))
			end

			if not page then
				res.not_found()
				return
			end

			res.html(layout and layout(page) or page.content)
		end,
	}
	return self
end

--- Create a new router.
---@return FluxRouter
function M.new()
	return setmetatable({ routes = {} }, Router)
end

return M
