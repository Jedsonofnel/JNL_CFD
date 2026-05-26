-- fvm/eq.lua - FVM constructors for jnl physics description layer
-- <jed@nelson.ac> // 2026-05-22

local M = {} -- internal module, re-exported by init.lua

-- deps
local E = require("jnl.core.expr")
local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")
local CEq = require("jnl.core.eq")
local FVexpr = require("jnl.fvm.expr")
local names = FVexpr.names

local make_term = CEq.make_term
local make_eq = CEq.make_eq
local is_term = CEq.is_term
local pop_config = CEq.pop_config
local term_deps = CEq.term_deps

--
-- FVM: Differential operators etc
--

local function to_field_name(v, ctx)
	if type(v) == "string" then
		V.field_name(v, ctx)
		return v
	end
	if E.is_expr(v) then
		local name = v._dep_name or (v.kind == "sym" and v.name)
		assert(type(name) == "string",
			(ctx or "to_field_name") .. ": expr has no resolvable field name")
		return name
	end
	error((ctx or "to_field_name") .. ": expected field name or name expr, got "
		.. type(v), 3)
end

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
	if scheme:upper() ~= "IMPLICIT" then
		error("Op.DDT scheme: no support for anything BUT implicit at the mo sorry")
	end

	local phi_raw = to_field_name(table.remove(args), "Op.ddt phi (last arg)")

	local coeff_exprs = {}
	for _, a in ipairs(args) do coeff_exprs[#coeff_exprs + 1] = E.from(a) end
	local coeff = #coeff_exprs > 0 and E.mul(table.unpack(coeff_exprs)) or nil

	---@type FvmDdtTerm
	return make_term({
		kind     = "ddt",
		coeff    = coeff,
		phi      = phi_raw,
		scheme   = scheme,
		_backend = "fvm",
		_deps    = term_deps(coeff, phi_raw, E.prev_name(phi_raw)),
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

	local phi_raw = to_field_name(table.remove(args), "Op.div phi (last arg)")

	-- scan remaining args for the single facewise flux
	local flux_expr, flux_idx
	for i, a in ipairs(args) do
		local e = E.from(a)

		if FVexpr.is_facewise(e) then
			assert(flux_idx == nil,
				"Op.div: only one facewise flux argument is allowed")
			flux_expr = e
			flux_idx  = i
		end
	end

	assert(flux_expr ~= nil,
		"Op.div: no facewise flux argument found (wrap your flux with FVMe.mwi or FVMe.face)")
	table.remove(args, flux_idx)

	local rho_exprs = {}
	for _, a in ipairs(args) do rho_exprs[#rho_exprs + 1] = E.from(a) end
	local coeff = #rho_exprs > 0 and E.mul(table.unpack(rho_exprs)) or nil

	local tvd_limiter = nil
	if scheme == "MINMOD" or scheme == "SUPERBEE" or scheme == "VAN-LEER" then
		tvd_limiter = scheme
		scheme = "UDS"
	end

	local extra = tvd_limiter and { phi_raw, names.grad(phi_raw) } or { phi_raw }
	local deps  = term_deps(coeff, table.unpack(extra))
	if flux_expr._dep_name then deps[flux_expr._dep_name] = true end

	---@type FvmDivTerm
	return make_term({
		kind     = "div",
		flux     = flux_expr,
		coeff    = coeff,
		phi      = phi_raw,
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

	local phi_raw = to_field_name(table.remove(args), "Op.lap phi (last arg)")

	local gamma_exprs = {}
	for _, a in ipairs(args) do gamma_exprs[#gamma_exprs + 1] = E.from(a) end
	local coeff = #gamma_exprs > 0 and E.mul(table.unpack(gamma_exprs)) or nil

	local extra = non_ortho and { phi_raw, names.grad(phi_raw) } or { phi_raw }

	---@type FvmLapTerm
	return make_term({
		kind         = "lap",
		coeff        = coeff,
		phi          = phi_raw,
		gamma_scheme = gamma_scheme,
		non_ortho    = non_ortho,
		_deps        = term_deps(coeff, table.unpack(extra)),
		_backend     = "fvm",
	})
end

---@return FvmSuTerm
function Op.su(...)
	local args = { ... }
	local config = pop_config(args)
	local integrated = config.integrated or false

	local exprs = {}
	for _, a in ipairs(args) do
		exprs[#exprs + 1] = E.from(a)
	end
	local combined = #exprs == 1 and exprs[1] or E.add(table.unpack(exprs))

	---@type FvmSuTerm
	return make_term({
		kind       = "su",
		expr       = combined,
		integrated = integrated,
		_deps      = term_deps(combined),
		_backend   = "fvm",
		_is_linear = false,
	})
end

---@return FvmSpTerm
function Op.sp(coeff, config)
	config = config or {}
	local integrated = config.integrated or false
	local expr = E.from(coeff)

	---@type FvmSpTerm
	return make_term({
		kind       = "sp",
		expr       = expr,
		integrated = integrated,
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
	local prefix = self.integrated and "∫Su" or "Su"
	return string.format("%s[%s]", prefix, E.pretty(self.expr))
end)

CEq.register_pretty("sp", function(self, field)
	---@cast self FvmSpTerm
	local prefix = self.integrated and "∫Sp" or "Sp"
	local phi_str = field or "phi"
	return string.format("%s[%s]%s%s", prefix, E.pretty(self.expr), G.mul, phi_str)
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

--
-- API
--

M._doc = "FVM differential operator constructors and equation assembler."

M._doc_subsection =
	"Build equations by passing Op.* terms to FVM.eq(). All operators take the field " ..
	"being solved as their last positional argument; a trailing config table is optional. " ..
	"Op.div requires exactly one facewise flux expression (FVMe.mwi or FVMe.face) among " ..
	"its arguments. The result of FVM.eq() is passed as the eq field in reg:field()."

M._types = {
	Op = {
		doc         = "FVM differential operator constructors; all return Term for use in FVM.eq()",
		constructor = "available as FVM.Op or local Op = FVM.Op",
		kind        = "table",
		methods     = {
			ddt = { args = "coeff?, ..., field, config?", ret = "Term", doc = "Implicit time derivative; config: { scheme='implicit' }" },
			div = { args = "flux:Expr, coeff?, field, config?", ret = "Term", doc = "Convection; flux must be facewise (mwi/face); config: { scheme='uds'|'cds'|'minmod'|'superbee'|'van-leer' }" },
			lap = { args = "coeff?, field, config?", ret = "Term", doc = "Laplacian; config: { gamma_scheme='linear'|'harmonic', non_ortho=false }" },
			su  = { args = "expr, config?", ret = "Term", doc = "Explicit source added to RHS; config: { integrated=false }" },
			sp  = { args = "coeff, config?", ret = "Term", doc = "Linearised implicit source added to diagonal; config: { integrated=false }" },
		},
	},
	Term = {
		doc         = "Assembled operator term; carry kind, coeff, phi, and _deps",
		constructor = "Op.ddt / Op.div / Op.lap / Op.su / Op.sp",
		kind        = "table",
		methods     = {
			pretty    = { args = "field_name?", ret = "string", doc = "Render term to human-readable string" },
			deps      = { args = "", ret = "string[]", doc = "Sorted field names this term depends on" },
			has_dep   = { args = "name:string", ret = "bool", doc = "True if name is a direct dependency" },
			is_linear = { args = "", ret = "bool", doc = "True for ddt/lap/div; false for su/sp unless overridden" },
		},
	},
	Eq = {
		doc         = "Assembled field equation holding terms, solver, and relaxation",
		constructor = "FVM.eq(...terms, config?)",
		kind        = "table",
		methods     = {
			pretty       = { args = "field_name?", ret = "string", doc = "Render equation block to string" },
			deps         = { args = "", ret = "string[]", doc = "Union of all term dependencies, sorted" },
			has_dep      = { args = "name:string", ret = "bool", doc = "True if any term depends on name" },
			terms_of     = { args = "kind:string", ret = "fun():Term?", doc = "Iterator over terms of a specific kind" },
			is_nonlinear = { args = "", ret = "bool", doc = "True if any term is nonlinear in phi" },
		},
	},
}

-- Note: FVM.eq itself is documented on the FVM facade (jnl.fvm)

return M
