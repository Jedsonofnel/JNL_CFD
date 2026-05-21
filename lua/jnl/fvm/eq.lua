-- fvm/eq.lua - FVM constructors for jnl physics description layer
-- <jed@nelson.ac> // 2026-05-08

local M = {} -- internal module, re-exported by init.lua

-- deps
local E = require("jnl.core.expr")
local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")

-- contract: equations hold terms and belong to fields
function E.is_eq(v)
	return type(v) == "table" and v._type == "eq"
end

-- contract: terms belong to equations
function E.is_term(v)
	return type(v) == "table" and v._type == "term"
end

--
-- Canonical name manglers for FMV intermediate fields
--

local function grad_name(field, component)
	if component ~= nil then
		return "__grad_" .. component .. ":" .. field
	end
	return "__grad_" .. field
end

local function face_name(field)
	return "__face_" .. field
end

local function mwi_name(U, p)
	return "__mwi_" .. U .. ":" .. p
end

local function diag_name(field, i)
	if i then return "__diag_" .. i .. ":" .. field end
	return "__diag_" .. field
end

local function div_name(field)
	return "__div_" .. field
end

local function div_mwi_name(U, p)
	return "__div_mwi_" .. U .. ":" .. p
end

-- Decoders return nil if name doesn't match pattern

local function is_grad(name)
	local comp, field = name:match("^__grad_([xy]):(.+)$")
	return comp, field
end

local function is_grad_parent(name)
	if name:match("^__grad_[xy]:") then return nil end
	return name:match("^__grad_(.+)$")
end

local function is_face(name)
	return name:match("^__face_(.+)$")
end

local function is_mwi(name)
	local U, p = name:match("^__mwi_(.+):(.+)$")
	return U, p
end

local function is_diag(name)
	local comp, field = name:match("^__diag_([xy]):(.+)$")
	if field then return field, comp end

	field = name:match("^__diag_(.+)$")
	if field then return field, nil end
	return nil, nil
end

local function is_div(name)
	if name:match("^__div_mwi_") then return nil end
	return name:match("^__div_(.+)$")
end

local function is_div_mwi(name)
	local U, p = name:match("^__div_mwi_(.+):(.+)$")
	return U, p
end

M.names = {
	grad = grad_name,
	face = face_name,
	mwi = mwi_name,
	diag = diag_name,
	div = div_name,
	div_mwi = div_mwi_name,
	is_grad = is_grad,
	is_grad_parent = is_grad_parent,
	is_face = is_face,
	is_mwi = is_mwi,
	is_diag = is_diag,
	is_div = is_div,
	is_div_mwi = is_div_mwi,
}

E.pretty_sym_fallback = function(name)
	do
		local comp, field = is_grad(name)
		if comp then
			return G.grad .. comp .. G.lparen .. E.pretty_sym(field) .. G.rparen
		end
	end
	do
		local field = is_grad_parent(name)
		if field then
			return G.grad .. "(" .. E.pretty_sym(field) .. ")"
		end
	end
	do
		local field = is_face(name)
		if field then
			return "<" .. "f:" .. E.pretty_sym(field) .. ">"
		end
	end
	do
		local U, p = is_mwi(name)
		if U then
			return "<" .. "mwi:" .. E.pretty_sym(U) .. "," .. E.pretty_sym(p) .. ">"
		end
	end
	do
		local field, comp = is_diag(name)
		if field then
			local inner = E.pretty_sym(field)
			if comp then inner = inner .. "." .. comp end
			return "<" .. "d:" .. inner .. ">"
		end
	end
	do
		local U, p = is_div_mwi(name)
		if U then
			return G.div .. G.lparen .. "<mwi:" .. U .. "," .. p .. ">" .. G.rparen
		end
	end
	do
		local field = is_div(name)
		if field then
			return G.div .. G.lparen .. E.pretty_sym(field) .. G.rparen
		end
	end
end

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
		deps[grad_name(phi)] = true
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
-- FVM related expressions (satisfy expression contract)
--

local Expr = {}
M.Expr = Expr

function Expr.grad(field, i)
	V.field_name(field, "E.grad field")
	assert(i == "x" or i == "y", "E.grad component must be 'x' or 'y'")
	return {
		kind = "grad",
		field = field,
		component = i,
		_type = "expr",
		_dep_name = grad_name(field), -- parent, not component
		_pretty = function()
			return G.grad .. i .. G.lparen .. field .. G.rparen
		end,
	}
end

function Expr.diag(field, i)
	V.field_name(field, "E.diag field")
	assert(i == nil or i == "x" or i == "y",
		"Expr.diag: component (i) must be nil or 'x' or 'y'")

	local display = i and (field .. "." .. i) or field

	return {
		kind = "diag",
		field = field,
		component = i,
		_type = "expr",
		_dep_name = diag_name(field, i),
		_pretty = function()
			return "<diag:" .. display .. ">"
		end,
	}
end

function Expr.mwi(U_name, p_name)
	V.field_name(U_name, "E.mwi U")
	V.field_name(p_name, "E.mwi p")
	return {
		kind = "mwi",
		U = U_name,
		p = p_name,
		_type = "expr",
		_dep_name = mwi_name(U_name, p_name),
		_pretty = function()
			return "<mwi:" .. U_name .. "," .. p_name .. ">"
		end,
	}
end

function Expr.div(field)
	V.field_name(field, "E.div field")
	return {
		kind = "div",
		field = field,
		_type = "expr",
		_dep_name = div_name(field),
		_pretty = function()
			return G.div .. G.lparen .. field .. G.rparen
		end,
	}
end

function Expr.div_mwi(U_name, p_name)
	V.field_name(U_name, "E.div_mwi U")
	V.field_name(p_name, "E.div_mwi p")
	return {
		kind = "div_mwi",
		U = U_name,
		p = p_name,
		_type = "expr",
		_dep_name = div_mwi_name(U_name, p_name),
		_pretty = function()
			return G.div .. G.lparen .. "<mwi:" .. U_name .. "," .. p_name .. ">" .. G.rparen
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
		if E.is_term(v) then
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
