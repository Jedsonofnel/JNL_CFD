-- core/eq.lua - base types for equation terms and equations
-- <jed@nelson.ac> // 2026-05-22

local M = {}

local E = require("jnl.core.expr")
local G = require("jnl.core.glyphs")

--
-- Term metatable
--

---@class Term
local Term = {}
Term.__index = Term


---@param v any
---@return boolean
local function is_term(v)
	return type(v) == "table" and getmetatable(v) == Term
end

---@param t table
---@return Term
local function make_term(t)
	return setmetatable(t, Term)
end

M.is_term   = is_term
M.make_term = make_term

--
-- Eq metatable
--

---@class Eq
local Eq    = {}
Eq.__index  = Eq

---@param v any
---@return boolean
local function is_eq(v)
	return type(v) == "table" and getmetatable(v) == Eq
end


---@param t table
---@return Eq
local function make_eq(t)
	return setmetatable(t, Eq)
end

M.is_eq   = is_eq
M.make_eq = make_eq

--
-- pop_config
--

---Remove and return a trailing config table from a vararg-collected args list.
---Distinguishes config tables from terms, equations, and expressions by the
---absence of those metatables.  Returns {} if no config is present.
---@param  args table   The collected vararg table (modified in place)
---@return table config The config table, or {}
local function pop_config(args)
	local last = args[#args]
	if #args > 0
		and type(last) == "table"
		and not is_term(last)
		and not is_eq(last)
		and not E.is_expr(last) then
		return table.remove(args)
	end
	return {}
end

M.pop_config = pop_config

--
-- term_deps
--

---Collect dependencies for a term: walks an optional coefficient expression
---and adds any extra named field strings.
---@param  expr Expr|nil        Optional coefficient expression to walk
---@param  ...  string          Additional field name dependencies
---@return table<string,true>
local function term_deps(expr, ...)
	local into = {}
	if expr then E.collect_deps(expr, into) end
	for _, v in ipairs({ ... }) do
		if type(v) == "string" then
			into[v] = true
		end
	end
	return into
end

M.term_deps = term_deps

--
-- Pretty-printing registry
--


---@alias PrettyFn fun(self: Term, field_name: string|nil): string

---@type table<string, table<string, PrettyFn>>
local pretty_registry = { default = {} } -- might have LaTeX eventually

---Register a pretty-printing function for a term kind.
---Called by backends (e.g. fvm/eq.lua) on load.
---@param kind   string    Term kind to register for
---@param fn     PrettyFn  Rendering function
---@param format string|nil  "default" (terminal) or "latex". Defaults to "default".
function M.register_pretty(kind, fn, format)
	local reg = pretty_registry[format or "default"]
	assert(reg, "register_pretty: unknown format '" .. tostring(format) .. "'")
	reg[kind] = fn
end

--
-- Term methods
--

---Render the term to a string.
---@param  field_name string|nil  The name of the field being solved (used by sp)
---@param  format     string|nil  "default"|"latex"
---@return string
function Term:pretty(field_name, format)
	local fn = pretty_registry[format or "default"][self.kind]
	if fn then return fn(self, field_name) end
	return "<?term:" .. tostring(self.kind) .. ">"
end

Term.__tostring = function(self) return self:pretty() end

---Return a sorted list of field names this term depends on.
---@return string[]
function Term:deps()
	local result = {}
	for name in pairs(self._deps or {}) do
		result[#result + 1] = name
	end
	table.sort(result)
	return result
end

---@param  name string
---@return boolean
function Term:has_dep(name)
	return (self._deps or {})[name] == true
end

---Returns true if this term is linear in phi.
---ddt/lap/div are linear by construction; su/sp default to false.
---Override by setting _is_linear on the term table.
---@return boolean
function Term:is_linear()
	if self._is_linear ~= nil then return self._is_linear end
	return self.kind == "ddt"
		or self.kind == "lap"
		or self.kind == "div"
end

--
-- Eq methods
--

local function eq_pretty(self, field_name, format)
	local lines  = {}
	local prefix = "eq" .. G.eq
	local pad    = string.rep(" ", #prefix)

	for i, term in ipairs(self.terms) do
		local s = term:pretty(field_name, format)
		if i == 1 then
			lines[#lines + 1] = prefix .. s
		else
			lines[#lines + 1] = pad .. G.add .. " " .. s
		end
	end
	return table.concat(lines, "\n")
end

---Render the equation to a string.
---@param  field_name string|nil
---@param  format     string|nil  "default"|"latex"
---@return string
function Eq:pretty(field_name, format)
	return eq_pretty(self, field_name, format)
end

Eq.__tostring = function(self) return eq_pretty(self) end


---Return a sorted list of all field names this equation depends on.
---@return string[]
function Eq:deps()
	local names = {}
	for name in pairs(self._deps or {}) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

---@param  name string
---@return boolean
function Eq:has_dep(name)
	return (self._deps or {})[name] == true
end

---Iterate over terms of a specific kind.
---@param  kind string
---@return fun(): Term|nil
function Eq:terms_of(kind)
	local i = 0
	return function()
		repeat
			i = i + 1
		until i > #self.terms or self.terms[i].kind == kind
		return self.terms[i]
	end
end

---Returns true if any term is nonlinear in phi.
---@return boolean
function Eq:is_nonlinear()
	for _, term in ipairs(self.terms) do
		if not term:is_linear() then return true end
	end
	return false
end

return M
