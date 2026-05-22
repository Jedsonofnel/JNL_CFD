-- fvm/eq.lua - FVM constructors for jnl physics description layer
-- <jed@nelson.ac> // 2026-05-22

local M = {} -- internal module, re-exported by init.lua

-- deps
local E = require("jnl.core.expr")
local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")
local CEq = require("jnl.core.eq")
local names = require("jnl.fvm.expr").names

local make_term = CEq.make_term
local make_eq = CEq.make_eq
local is_term = CEq.is_term
local pop_config = CEq.pop_config
local term_deps = CEq.term_deps

--
-- FVM: Differential operators etc
--

local Op = {}
M.Op = Op

local ddt_scms = {
	IMPLICIT = true,
	EXPLICIT = true,
	CRANK_NICHOLSON = true,
}

---@return FvmDdtTerm
function Op.ddt(...)
	local args = { ... }
	if #args == 0 then error("Op.ddt: requires at least a field name", 2) end

	local config = pop_config(args)
	local scheme = V.in_enum(ddt_scms, config.scheme or "implicit", "Op.ddt scheme")

	local phi = E.from(table.remove(args))

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	---@type FvmDdtTerm
	return make_term({
		kind     = "ddt",
		coeff    = coeff,
		phi      = phi,
		scheme   = scheme,
		_backend = "fvm",
		_deps    = term_deps(coeff, phi.name, E.prev_name(phi.name)),
	})
end

local div_scms = {
	UDS = true,
	CDS = true,
	MINMOD = true,
	SUPERBEE = true,
	["VAN-LEER"] = true,
}

---@return FvmDivTerm
function Op.div(...)
	local args = { ... }
	if #args == 0 then error("Op.div: requires at least a field name", 2) end

	local config = pop_config(args)
	local raw_scheme = (config.scheme or "uds"):upper()
	local scheme = V.in_enum(div_scms, raw_scheme, "Op.div scheme")

	local phi = E.from(table.remove(args))
	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	local deps = term_deps(coeff, phi.name)

	local tvd_limiter = nil
	if scheme == "MINMOD" or scheme == "SUPERBEE" or scheme == "VAN-LEER" then
		tvd_limiter = scheme
		scheme = "UDS"

		deps[names.grad(phi.name)] = true
	end

	---@type FvmDivTerm
	return make_term({
		kind     = "div",
		coeff    = coeff,
		phi      = E.from(phi),
		scheme   = scheme,
		tvd      = tvd_limiter,
		_deps    = deps,
		_backend = "fvm",
	})
end

local lap_gamma_schemes = {
	LINEAR   = true,
	HARMONIC = true,
}

---@return FvmLapTerm
function Op.lap(...)
	local args = { ... }
	if #args == 0 then error("Op.lap: requires at least a field name", 2) end

	local config = pop_config(args)
	local gamma_scheme = V.in_enum(
		lap_gamma_schemes,
		config.gamma_scheme or "linear",
		"Op.lap gamma_scheme")
	local non_ortho = config.non_ortho or false

	local phi = E.from(table.remove(args))

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	local deps = term_deps(coeff, phi.name)
	if non_ortho then
		deps[names.grad(phi.name)] = true
	end

	---@type FvmLapTerm
	return make_term({
		kind         = "lap",
		coeff        = coeff,
		phi          = E.from(phi),
		gamma_scheme = gamma_scheme,
		non_ortho    = non_ortho,
		_deps        = deps,
		_backend     = "fvm",
	})
end

---@return FvmSuTerm
function Op.su(...)
	local args = { ... }
	local exprs = {}
	for _, a in ipairs(args) do
		exprs[#exprs + 1] = E.from(a)
	end
	local combined = #exprs == 1 and exprs[1] or E.add(table.unpack(exprs))
	---@type FvmSuTerm
	return make_term({
		kind       = "su",
		expr       = combined,
		_deps      = term_deps(combined),
		_backend   = "fvm",
		_is_linear = false,
	})
end

---@return FvmSpTerm
function Op.sp(coeff)
	local expr = E.from(coeff)
	---@type FvmSpTerm
	return make_term({
		kind       = "sp",
		expr       = expr,
		_deps      = term_deps(expr),
		_backend   = "fvm",
		_is_linear = false,
	})
end

--
-- Pretty printing
--


CEq.register_pretty("ddt", function(self)
	local inner = self.coeff
		and E.pretty(E.mul(self.coeff, self.phi))
		or E.pretty(self.phi)
	return string.format("%s[%s]", G.ddt, inner)
end)

CEq.register_pretty("div", function(self)
	---@cast self FvmDivTerm
	local inner = self.coeff
		and E.pretty(E.mul(self.coeff, self.phi))
		or E.pretty(self.phi)
	local scheme_str = self.tvd and ("[" .. self.tvd:lower() .. "]") or ""
	return string.format("%s%s[%s]", G.div, scheme_str, inner)
end)

CEq.register_pretty("lap", function(self)
	---@cast self FvmLapTerm
	local inner = self.coeff
		and E.pretty(E.mul(self.coeff, self.phi))
		or E.pretty(self.phi)
	local flags = {}
	if self.gamma_scheme ~= "LINEAR" then
		flags[#flags + 1] = self.gamma_scheme:lower()
	end
	if self.non_ortho then
		flags[#flags + 1] = "non-ortho"
	end
	local flag_str = #flags > 0 and ("[" .. table.concat(flags, ",") .. "]") or ""
	return string.format("%s%s[%s]", G.lap, flag_str, inner)
end)

CEq.register_pretty("su", function(self, _)
	---@cast self FvmSuTerm
	return E.pretty(self.expr)
end)

CEq.register_pretty("sp", function(self, field)
	---@cast self FvmSpTerm
	local phi_str = field or "phi"
	return string.format("%s[%s]%s%s", G.sp, E.pretty(self.expr), G.mul, phi_str)
end)

--
-- FVM: Create an equation
--

local eq_solvers = {
	CG = true,
	BICGSTAB = true,
}

local function eq(...)
	local args = { ... }
	local config = pop_config(args)

	local terms = {}
	for i, v in ipairs(args) do
		if is_term(v) then
			terms[#terms + 1] = v
		elseif E.is_expr(v) or type(v) == "number" then
			terms[#terms + 1] = Op.su(v)
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

	return make_eq({
		terms = terms,
		relax = config.relax,
		solver = solver,
		_deps = deps,
		_backend = "fvm",
	})
end

M.Eq = eq

return M
