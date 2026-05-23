-- registry.lua - registry of symbols for physics problems
-- <jed@nelson.ac> // 2026-05-11

-- deps
local E = require("jnl.core.expr")
local G = require("jnl.core.glyphs")
local V = require("jnl.core.validation")

--
-- Types of things that go into registry
--

local Constant = {}
Constant.__index = Constant

function Constant:_pretty()
	return string.format("%-12s %g", self.name, self.value)
end

local Expression = {}
Expression.__index = Expression

function Expression:_pretty()
	return string.format("%-12s %s", self.name, self.expr)
end

local Correction = {}
Correction.__index = Correction

function Correction:_pretty()
	return string.format("%-12s [correction] %s <- %s",
		"__correct_" .. self.target,
		self.target,
		self.expr)
end

local Field = {}
Field.__index = Field

function Field:_pretty()
	local lines = {}
	local function line(s) lines[#lines + 1] = s end

	-- header
	local flags = {}
	if self.region then flags[#flags + 1] = "region:" .. self.region end
	local flag_str = #flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or ""
	line(self.name .. flag_str)

	-- equation block
	if self.eq and self.eq._pretty then
		line(self.eq:_pretty(self.name, G.indent))
	end

	-- solver properties
	if self.eq then
		local props = {
			{ "solver", self.eq.solver or "?" },
			{ "relax",  self.eq.relax and string.format("%g", self.eq.relax) or "none" },
		}
		if self.bcs then props[#props + 1] = { "bcs", "<bc-table>" } end
		if self.region then props[#props + 1] = { "region", self.region } end

		local max_k = 0
		for _, p in ipairs(props) do
			if #p[1] > max_k then max_k = #p[1] end
		end
		for _, p in ipairs(props) do
			local pad = string.rep(" ", max_k - #p[1])
			line(G.indent .. p[1] .. pad .. "  " .. p[2])
		end
	end

	return table.concat(lines, "\n")
end

local Uniform = {}
Uniform.__index = Uniform

local Vector = {}
Vector.__index = Vector

function Vector:_pretty()
	return string.format("%-12s vector(%s)", self.name,
		table.concat(self.components, ", "))
end

local Intermediate = {}
Intermediate.__index = Intermediate

function Intermediate:_pretty()
	local dep_str = #self.deps > 0
		and table.concat(self.deps, ", ") or "-"
	return string.format("%-12s [synthetic: %s] <- %s",
		self.name, self.itype, dep_str)
end

--
-- Registry: just a table of syms
--

local R = {}
R.__index = R

function R.new()
	return setmetatable({}, R)
end

function R:define(name, sym, proto)
	proto = proto or {}
	sym._type = "sym"
	sym.name = name
	self[name] = setmetatable(sym, proto)
end

function R:constant(name, value)
	V.identifier(name, "R:constant name")
	V.typeof(value, "number", "constant value")
	self:define(name, { kind = "constant", value = value }, Constant)
end

-- TODO: figure out the interface
-- has effect that if it's used in any FVM or further things then you have to
-- call different methods etc (ie laplacian_region(k_air) AND laplacian_region(k_solid))
-- function R:region_property(sym, spec)
-- end

function R:expression(name, expr)
	V.identifier(name, "R:expression name")
	self:define(name, { kind = "expression", expr = expr }, Expression)
end

function R:correction(name, expr)
	V.identifier(name, "R:correction target")
	assert(E.is_expr(expr),
		"R:correction: expected an expression for '" .. name .. "'")
	local sym_name = "__correct_" .. name
	self:define(sym_name, {
		kind   = "correction",
		target = name,
		expr   = expr,
	}, Correction)
end

function R:field(name, spec)
	V.field_name(name, "R:field name")

	if spec.region ~= nil then
		V.typeof(spec.region, "string", "field '" .. name .. "' region")
	end

	if spec.eq == nil then
		error("R:field expects an equation field", 2)
	end

	self:define(name, {
		kind = "field",
		initial = spec.initial or 0.0,
		bcs = spec.bcs,
		region = spec.region,
		eq = spec.eq,
		clip = spec.clip,
	}, Field)
end

function R:uniform(name, value)
	V.field_name(name, "R:uniform name")
	V.typeof(value, "number", "uniform value")
	self:define(name, {
		kind = "uniform",
		value = value,
	}, Uniform)
end

function R:vector(name, components)
	V.field_name(name, "R:vector name")
	assert(type(components) == "table" and #components >= 2,
		"R:vector components: must be a list of at least 2 field names")
	for _, c in ipairs(components) do
		assert(self[c],
			"R:vector '" .. name .. "': component '" .. c .. "' not yet registered")
	end
	self:define(name, { kind = "vector", components = components }, Vector)
end

--- Add an Intermediate to registry, for use by compiler backend.
function R:intermediate(name, itype, deps, opts)
	V.internal_identifier(name, "R:intermediate name")
	opts = opts or {}
	self:define(name, {
		kind = "intermediate",
		itype = itype,
		deps = deps,
		accessor = opts.accessor or false, -- accessor means "invisible to algorithm" eg diag
	}, Intermediate)
end

--
-- Helpers
--

function R:query(name)
	return self[name]
end

function R:expect(name)
	local sym = self[name]
	assert(sym, "registry: unknown symbol '" .. name .. "'")
	return sym
end

function R:listing()
	local parts = {}
	local names = {}
	for name in pairs(self) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		parts[#parts + 1] = self[name]:_pretty()
	end
	return table.concat(parts, "\n")
end

function R:print()
	print(self:listing())
end

function R:deps_of(name)
	local sym = self:expect(name)
	local into = {}

	if sym.kind == "constant" then
		return {}
	elseif sym.kind == "expression" then
		local names = sym.expr:deps()
		for _, n in ipairs(names) do into[n] = true end
	elseif sym.kind == "correction" then
		local names = sym.expr:deps()
		for _, n in ipairs(names) do into[n] = true end
	elseif sym.kind == "field" and sym.eq then
		for n in pairs(sym.eq._deps or {}) do into[n] = true end
	elseif sym.kind == "intermediate" then
		for _, n in ipairs(sym._deps or {}) do into[n] = true end
	end

	local result = {}
	for n in pairs(into) do result[#result + 1] = n end
	table.sort(result)
	return result
end

function R:depends_on(name)
	local result = {}
	for other_name in pairs(self) do
		local deps = self:deps_of(other_name)
		for _, d in ipairs(deps) do
			if d == name then
				result[#result + 1] = other_name
				break
			end
		end
	end

	table.sort(result)
	return result
end

function R:dep_listing()
	local lines = {}
	local names = {}
	for name in pairs(self) do names[#names + 1] = name end
	table.sort(names)

	for _, name in ipairs(names) do
		local deps = self:deps_of(name)
		local dep_str = #deps > 0 and table.concat(deps, ", ") or "-"
		lines[#lines + 1] = string.format("%-12s -> { %s }", name, dep_str)
	end

	return table.concat(lines, "\n")
end

--- Validates that all symbols in the registry are correctly accounted for.
function R:validate()
	local errors = {}

	for name, sym in pairs(self) do
		if type(sym) ~= "table" then goto continue end

		local deps = self:deps_of(name)
		for _, dep in ipairs(deps) do
			if not self[dep] then
				errors[#errors + 1] = string.format(
					"  '%s' depends on unregistered symbol '%s'", name, dep)
			end
		end

		if sym.kind == "correction" then
			local target = self[sym.target]
			if not target then
				errors[#errors + 1] = string.format(
					"  correction '%s' targets unregistered field '%s'",
					name, sym.target)
			elseif target.kind ~= "field" then
				errors[#errors + 1] = string.format(
					"  correction '%s' targets '%s' which is a %s, not a field",
					name, sym.target, target.kind)
			end
		end

		::continue::
	end

	if #errors > 0 then
		error("registry validation failed:\n" .. table.concat(errors, "\n"), 2)
	end
end

return R
