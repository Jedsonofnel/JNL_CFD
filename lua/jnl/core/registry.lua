-- registry.lua - registry of symbols for physics problems
-- <jed@nelson.ac> // 2026-05-11

local R = {}

-- deps
local E = require("core.expr")
local G = require("display.glyphs")
local V = require("core.validation")

-- contract: equations hold terms and belong to fields
function R.is_eq(v)
	return type(v) == "table" and v._type == "eq"
end

-- contract: terms belong to equations
function R.is_term(v)
	return type(v) == "table" and v._type == "term"
end

--
-- Types of things that go into registry
--

-- everything is a symbol (so can stash helpers on it)
local Symbol = {}
Symbol.__index = Symbol

function Symbol:is_prognostic()
	return self.prognostic or false
end

function Symbol:is_intermediate()
	return self.kind == "intermediate"
end

local Constant = setmetatable({}, Symbol)
Constant.__index = Constant

function Constant:pretty_str()
	return string.format("%-12s %g", self.name, self.value)
end

local Expression = setmetatable({}, Symbol)
Expression.__index = Expression

function Expression:pretty_str()
	return string.format("%-12s %s", self.name, E.pretty(self.expr))
end

local Field = setmetatable({}, Symbol)
Field.__index = Field

function Field:pretty_str()
	local lines = {}
	local function line(s) lines[#lines + 1] = s end

	-- header
	local flags = {}
	if self.prognostic then flags[#flags + 1] = "prognostic" end
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
			{ "solver",  self.eq.solver or "?" },
			{ "relax",   self.eq.relax and string.format("%g", self.eq.relax) or "none" },
			{ "backend", self.eq._backend or "?" },
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

--
-- Registry: Putting it all together
--

R.__index = R

function R.new()
	return setmetatable({ syms = {} }, R)
end

function R:constant(name, value)
	V.identifier(name, "constant name")
	V.typeof(value, "number", "constant value")
	self.syms[name] = setmetatable({
		name = name,
		kind = "constant",
		value = value,
		_type = "sym",
	}, Constant)
end

-- TODO: figure out the interface
-- has effect that if it's used in any FVM or further things then you have to
-- call different methods etc (ie laplacian_region(k_air) AND laplacian_region(k_solid))
-- function R:region_property(sym, spec)
-- end

function R:expression(name, expr)
	V.identifier(name, "expression name")
	self.syms[name] = setmetatable({
		name = name,
		kind = "expression",
		expr = expr,
		_type = "sym",
	}, Expression)
end

function R:field(name, eq_or_spec)
	V.identifier(name, "field name")

	local eq, spec
	if R.is_eq(eq_or_spec) then
		eq   = eq_or_spec
		spec = {}
	elseif type(eq_or_spec) == "table" and R.is_eq(eq_or_spec.eq) then
		eq   = eq_or_spec.eq
		spec = eq_or_spec
	else
		error(string.format(
			"field '%s': expected FVM.eq(...) result or {eq=FVM.eq(...), ...}",
			name), 2)
	end

	if spec.region ~= nil then
		V.typeof(spec.region, "string", "field '" .. name .. "' region")
	end

	self.syms[name] = setmetatable({
		kind = "field",
		prognostic = true,
		name = name,
		bcs = spec.bcs,
		region = spec.region,
		initial = spec.initial or 0.0,
		eq = eq,
		_type = "sym",
	}, Field)
end

-- no such thing as a vector - just desugars to two scalars?
-- function R:vector(sym, spec)
--  TODOOOOOO (complex)
-- end

function R:query(name)
	return self.syms[name]
end

return R
