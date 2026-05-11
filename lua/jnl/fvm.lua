-- jnl/fvm.lua - FVM constructors for jnl physics description layer
-- <jed@nelson.ac> // 2026-05-08

local FVM = {}

-- deps
local E = require("core.expr")
local V = require("core.validation")
local R = require("core.registry")
local G = require("display.glyphs")

--
-- Canonical name manglers for FMV intermediate fields
--

local function grad_name(field, component)
	return "__grad_" .. component .. "_" .. field
end

local function face_name(field)
	return "__face_" .. field
end

local function mwi_name(U, p)
	return "__mwi_" .. U .. "_" .. p
end

local function prev_name(field)
	return "__prev_" .. field
end

local function diag_name(field, i)
	if i then return "__diag_" .. i .. "_" .. field end
	return "__diag_" .. field
end

-- Decoders return nil if name doesn't match pattern

local function is_grad(name)
	local comp, field = name:match("^__grad_([xy])_(.+)$")
	return comp, field
end

local function is_face(name)
	return name:match("^__face_(.+)$")
end

local function is_mwi(name)
	local U, p = name:match("^__mwi_(.+)_(.+)$")
	return U, p
end

local function is_prev(name)
	return name:match("^__prev_(.+)$")
end

local function is_diag(name)
	local comp, field = name:match("^__diag_([xy])_(.+)$")
	if field then return field, comp end

	field = name:match("^__diag_(.+)$")
	if field then return field, nil end
	return nil, nil
end

--
-- FVM: Differential operators etc
--

local Op = {}
FVM.Op = Op

-- helper for getting configs
local function pop_config(args)
	if #args > 0
		and type(args[#args]) == "table"
		and args[#args]._type == nil then
		return table.remove(args)
	end
	return {}
end

local dt_scms = {
	IMPLICIT = true,
	EXPLICIT = true,
	CRANK_NICHOLSON = true,
}

function Op.dt(...)
	local args = { ... }
	if #args == 0 then
		error("Op.dt: requires at least a field name", 2)
	end

	local config = pop_config(args)
	local scheme = V.in_enum(dt_scms, config.scheme or "implicit", "Op.dt scheme")

	local phi = table.remove(args)
	V.identifier(phi)

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	return {
		kind     = "dt",
		coeff    = coeff,
		phi      = E.from(phi),
		scheme   = scheme,
		_type    = "term",
		_backend = "fvm",
		_pretty  = function()
			local inner = coeff
				and E.pretty(E.mul(coeff, phi))
				or E.pretty(phi)
			return string.format("%s[%s]", G.dt, inner)
		end,
	}
end

local div_scms = {
	UDS = true,
	CDS = true,
}

-- TODO: convert to config table form
function Op.div(...)
	local args = { ... }
	if #args == 0 then
		error("Op.div: requires at least a field name", 2)
	end

	local config = pop_config(args)
	local scheme = V.in_enum(div_scms, config.scheme or "uds", "Op.div scheme")

	local phi = table.remove(args)
	V.identifier(phi)

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	return {
		kind     = "div",
		coeff    = coeff,
		phi      = E.from(phi),
		scheme   = scheme,
		_type    = "term",
		_backend = "fvm",
		_pretty  = function()
			local inner = coeff
				and E.pretty(E.mul(coeff, phi))
				or E.pretty(phi)
			return string.format("%s[%s]", G.div, inner)
		end,
	}
end

-- TODO scheme selection (linear or harmonic gamma interp?)
function Op.lap(...)
	local args = { ... }
	if #args == 0 then
		error("Op.lap: requires at least a field name", 2)
	end

	local config = pop_config(args)
	-- TODO: get lap scheme (linear/harmonic gamma interp)

	local phi = table.remove(args)
	V.identifier(phi)

	local coeff = #args > 0 and E.mul(table.unpack(args)) or nil

	return {
		kind     = "lap",
		coeff    = coeff,
		phi      = E.from(phi),
		_type    = "term",
		_backend = "fvm",
		_pretty  = function()
			local inner = coeff
				and E.pretty(E.mul(coeff, phi))
				or E.pretty(phi)
			return string.format("%s[%s]", G.lap, inner)
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
FVM.Expr = Expr

function Expr.grad(field, i)
	V.identifier(field, "E.grad field")
	assert(i == "x" or i == "y",
		"E.grad component must be 'x' or 'y'")
	return {
		kind = "grad",
		field = field,
		component = i,
		_type = "expr",
		_pretty = function()
			return G.grad .. i .. G.lparen .. field .. G.rparen
		end,
		_refs = { grad_name(field, i) },
	}
end

function Expr.prev(field)
	V.identifier(field, "E.prev field")
	return {
		kind = "prev",
		field = field,
		_type = "expr",
		_pretty = function()
			return field .. G.prev
		end,
		_refs = { prev_name(field) },
	}
end

function Expr.diag(field, i)
	V.identifier(field, "E.diag field")
	assert(i == nil or i == "x" or i == "y",
		"Expr.diag: component (i) must be nil or 'x' or 'y'")

	local mangled = diag_name(field, i)
	local display = i and (field .. "." .. i) or field

	return {
		kind = "diag",
		field = field,
		component = i,
		_type = "expr",
		_pretty = function()
			return "<diag:" .. display .. ">"
		end,
		_refs = { mangled },
	}
end

function Expr.mwi(U_name, p_name)
	V.identifier(U_name, "E.mwi U")
	V.identifier(p_name, "E.mwi p")
	return {
		kind = "mwi",
		U = U_name,
		p = p_name,
		_type = "expr",
		_pretty = function()
			return "<mwi:" .. U_name .. "," .. p_name .. ">"
		end,
		_refs = {} -- TODO
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


function FVM.eq(...)
	local args = { ... }
	local config = pop_config(args)

	local terms = {}
	for i, v in ipairs(args) do
		if R.is_term(v) then
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

	return {
		terms = terms,
		relax = config.relax,
		solver = solver,
		_type = "eq",
		_backend = "fvm",
		_pretty = eq_pretty,
	}
end

return FVM
