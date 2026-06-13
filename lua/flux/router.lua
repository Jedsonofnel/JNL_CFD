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

--- Create a new router.
---@return FluxRouter
function M.new()
	return setmetatable({ routes = {} }, Router)
end

return M
