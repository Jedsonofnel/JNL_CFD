-- fvm/eq.lua - FVM constructors for jnl physics description layer
-- <jed@nelson.ac> // 2026-05-08

local M = {} -- internal module, re-exported by init.lua

-- deps
local E = require("jnl.core.expr")
local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")

local names = require("jnl.fvm.expr").names

--
-- FVM: Differential operators etc
--

local Op = {}
M.Op = Op

-- helper for getting configs
local function pop_config(args)
	if #args > 0
		and type(args[#args]) == "table"
		and args[#args]._type == nil then
		return table.remove(args)
	end
	return {}
end

--- Collect dependencies of an FVM term
--- @param expr table|nil Every term will have an expression coefficient
--- @param ... string Any other dependencies
local function term_deps(expr, ...)
	local rest = { ... }
	local into = {}

	if expr then E.collect_deps(expr, into) end
	for _, v in ipairs(rest) do
		if type(v) == "string" then
			into[v] = true
		end
	end
	return into
end

local ddt_scms = {
	IMPLICIT = true,
	EXPLICIT = true,
	CRANK_NICHOLSON = true,
}

function Op.ddt(...)
	local args = { ... }
	if #args == 0 then
		error("Op.ddt: requires at least a field name", 2)
	end

	local config = pop_config(args)
	local scheme = V.in_enum(ddt_scms, config.scheme or "implicit", "Op.ddt scheme")

	local phi = table.remove(args)

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	return {
		kind     = "ddt",
		coeff    = coeff,
		phi      = E.from(phi),
		scheme   = scheme,
		_type    = "term",
		_backend = "fvm",
		_deps    = term_deps(coeff, phi, E.prev_name(phi)),
		_pretty  = function()
			local inner = coeff
				and E.pretty(E.mul(coeff, phi))
				or E.pretty(phi)
			return string.format("%s[%s]", G.ddt, inner)
		end,
	}
end

local div_scms = {
	UDS = true,
	CDS = true,
}

function Op.div(...)
	local args = { ... }
	if #args == 0 then
		error("Op.div: requires at least a field name", 2)
	end

	local config = pop_config(args)
	local scheme = V.in_enum(div_scms, config.scheme or "uds", "Op.div scheme")

	local phi = table.remove(args)

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	return {
		kind     = "div",
		coeff    = coeff,
		phi      = E.from(phi),
		scheme   = scheme,
		_type    = "term",
		_deps    = term_deps(coeff, phi),
		_backend = "fvm",
		_pretty  = function()
			local inner = coeff
				and E.pretty(E.mul(coeff, phi))
				or E.pretty(phi)
			return string.format("%s[%s]", G.div, inner)
		end,
	}
end

local lap_gamma_schemes = {
	LINEAR   = true,
	HARMONIC = true,
}

function Op.lap(...)
	local args = { ... }
	if #args == 0 then
		error("Op.lap: requires at least a field name", 2)
	end

	local config = pop_config(args)
	local gamma_scheme = V.in_enum(
		lap_gamma_schemes,
		config.gamma_scheme or "linear",
		"Op.lap gamma_scheme")
	local non_ortho = config.non_ortho or false

	local phi = table.remove(args)

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	local deps = term_deps(coeff, phi)
	if non_ortho then
		deps[names.grad(phi)] = true
	end

	return {
		kind         = "lap",
		coeff        = coeff,
		phi          = E.from(phi),
		gamma_scheme = gamma_scheme,
		non_ortho    = non_ortho,
		_type        = "term",
		_deps        = deps,
		_backend     = "fvm",
		_pretty      = function()
			local inner = coeff
				and E.pretty(E.mul(coeff, phi))
				or phi
			local flags = {}
			if gamma_scheme ~= "LINEAR" then
				flags[#flags + 1] = gamma_scheme:lower()
			end
			if non_ortho then
				flags[#flags + 1] = "non-ortho"
			end
			local flag_str = #flags > 0
				and ("[" .. table.concat(flags, ",") .. "]")
				or ""
			return string.format("%s%s[%s]", G.lap, flag_str, inner)
		end,
	}
end

function Op.su(...)
	local args = { ... }
	local exprs = {}
	for _, a in ipairs(args) do
		exprs[#exprs + 1] = E.from(a)
	end
	local combined = #exprs == 1 and exprs[1] or E.add(table.unpack(exprs))
	return {
		kind     = "su",
		expr     = combined,
		_type    = "term",
		_deps    = term_deps(combined),
		_backend = "fvm",
		_pretty  = function()
			return E.pretty(combined)
		end,
	}
end

function Op.sp(coeff)
	local expr = E.from(coeff)
	return {
		kind     = "sp",
		expr     = expr,
		_deps    = term_deps(expr),
		_type    = "term",
		_backend = "fvm",
		_pretty  = function(field)
			local phi_str = field or "phi"
			return string.format("%s[%s]%s%s",
				G.sp, E.pretty(expr), G.mul, phi_str)
		end,
	}
end

--
-- FVM: Create an equation
--

local eq_solvers = {
	CG = true,
	BICGSTAB = true,
}

local function eq_pretty(self, field_name, indent)
	indent = indent or ""
	local lines = {}
	local prefix = "eq" .. G.eq
	local continuation = indent .. string.rep(" ", #("eq" .. G.eq))

	for i, term in ipairs(self.terms) do
		local term_str = term._pretty(field_name)
		if i == 1 then
			lines[#lines + 1] = indent .. prefix .. term_str
		else
			lines[#lines + 1] = continuation .. "+ " .. term_str
		end
	end
	return table.concat(lines, "\n")
end


local function eq(...)
	local args = { ... }
	local config = pop_config(args)

	local terms = {}
	for i, v in ipairs(args) do
		if type(v) == "table" and v._type == "term" then
			terms[#terms + 1] = v
		elseif E.is_expr(v) or type(v) == "number" then
			terms[#terms + 1] = Op.su(v) -- coerce bare expr to Su
		else
			error(string.format("FVM.eq: arg %d is not a term or expression", i), 2)
		end
	end

	assert(#terms > 0, "FVM.eq: must contain at least one term")

	if config.relax ~= nil then
		assert(type(config.relax) == "number"
			and config.relax > 0 and config.relax <= 1,
			"FVM.eq: relax must be in (0, 1]")
	end

	local solver = V.in_enum(eq_solvers, config.solver or "bicgstab", "FVM.eq solver")

	local deps = {}
	for _, term in ipairs(terms) do
		for name in pairs(term._deps or {}) do
			deps[name] = true
		end
	end

	return {
		terms = terms,
		relax = config.relax,
		solver = solver,
		_deps = deps,
		_type = "eq",
		_backend = "fvm",
		_pretty = eq_pretty,
	}
end

M.Eq = eq

return M
