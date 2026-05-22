-- fvm/expr.lua - FVM flavoured expressions
-- <jed@nelson.ac> // 2026-05-22

local M = {}

-- deps
local V = require("jnl.core.validation")
local E = require("jnl.core.expr")
local G = require("jnl.core.glyphs")

--
-- Name manglers
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
-- Constructors
--

function M.grad(field, i)
	V.field_name(field, "E.grad field")
	assert(i == "x" or i == "y", "E.grad component must be 'x' or 'y'")
	return E.make_expr({
		kind = "grad",
		field = field,
		component = i,
		_dep_name = grad_name(field), -- parent, not component
		_pretty = function()
			return G.grad .. i .. G.lparen .. field .. G.rparen
		end,
	})
end

function M.diag(field, i)
	V.field_name(field, "E.diag field")
	assert(i == nil or i == "x" or i == "y",
		"Expr.diag: component (i) must be nil or 'x' or 'y'")

	local display = i and (field .. "." .. i) or field

	return E.make_expr({
		kind = "diag",
		field = field,
		component = i,
		_dep_name = diag_name(field, i),
		_pretty = function()
			return "<diag:" .. display .. ">"
		end,
	})
end

function M.mwi(U_name, p_name)
	V.field_name(U_name, "E.mwi U")
	V.field_name(p_name, "E.mwi p")
	return E.make_expr({
		kind = "mwi",
		U = U_name,
		p = p_name,
		_dep_name = mwi_name(U_name, p_name),
		_pretty = function()
			return "<mwi:" .. U_name .. "," .. p_name .. ">"
		end,
	})
end

function M.div(field)
	V.field_name(field, "E.div field")
	return E.make_expr({
		kind = "div",
		field = field,
		_dep_name = div_name(field),
		_pretty = function()
			return G.div .. G.lparen .. field .. G.rparen
		end,
	})
end

function M.div_mwi(U_name, p_name)
	V.field_name(U_name, "E.div_mwi U")
	V.field_name(p_name, "E.div_mwi p")
	return E.make_expr({
		kind = "div_mwi",
		U = U_name,
		p = p_name,
		_dep_name = div_mwi_name(U_name, p_name),
		_pretty = function()
			return G.div .. G.lparen .. "<mwi:" .. U_name .. "," .. p_name .. ">" .. G.rparen
		end,
	})
end

return M
