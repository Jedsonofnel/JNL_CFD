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

---@param field string
---@param component string?
local function grad_name(field, component)
	if component ~= nil then
		return "__grad_" .. component .. ":" .. field
	end
	return "__grad_" .. field
end

---@param field string
local function face_name(field)
	return "__face_" .. field
end

---@param U string
---@param p string
local function mwi_name(U, p)
	return "__mwi_" .. U .. ":" .. p
end

---@param field string
---@param i string?
local function diag_name(field, i)
	if i then return "__diag_" .. i .. ":" .. field end
	return "__diag_" .. field
end

---@param field string
local function div_name(field)
	return "__div_" .. field
end

---@param U string
---@param p string
local function div_mwi_name(U, p)
	return "__div_mwi_" .. U .. ":" .. p
end

-- Decoders return nil if name doesn't match pattern

---@param name string
---@return string, string
local function is_grad(name)
	local comp, field = name:match("^__grad_([xy]):(.+)$")
	return comp, field
end

---@param name string
---@return string?
local function is_grad_parent(name)
	if name:match("^__grad_[xy]:") then return nil end
	return name:match("^__grad_(.+)$")
end

---@param name string
---@return string
local function is_face(name)
	return name:match("^__face_(.+)$")
end

---@param name string
---@return string, string
local function is_mwi(name)
	local U, p = name:match("^__mwi_(.+):(.+)$")
	return U, p
end

---@param name string
---@return string?, string?
local function is_diag(name)
	local comp, field = name:match("^__diag_([xy]):(.+)$")
	if field then return field, comp end

	field = name:match("^__diag_(.+)$")
	if field then return field, nil end
	return nil, nil
end

---@param name string
---@return string?
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

--
-- Pretty printing
--

local function pretty_grad(field, comp)
	if comp then
		return G.grad .. comp .. G.lparen .. E.pretty_sym(field) .. G.rparen
	end
	return G.grad .. G.lparen .. E.pretty_sym(field) .. G.rparen
end

local function pretty_face(field)
	return "<" .. "f:" .. E.pretty_sym(field) .. ">"
end

local function pretty_mwi(U, p)
	return "<" .. "mwi:" .. E.pretty_sym(U) .. "," .. E.pretty_sym(p) .. ">"
end

local function pretty_diag(field, comp)
	local inner = E.pretty_sym(field)
	if comp then inner = inner .. "." .. comp end
	return "<" .. "d:" .. inner .. ">"
end

local function pretty_div_mwi(U, p)
	return G.div .. G.lparen .. "<mwi:" .. U .. "," .. p .. ">" .. G.rparen
end

local function pretty_div(field)
	return G.div .. G.lparen .. E.pretty_sym(field) .. G.rparen
end

E.pretty_sym_fallback = function(name)
	do
		local comp, field = is_grad(name)
		if comp then return pretty_grad(field, comp) end
	end
	do
		local field = is_grad_parent(name)
		if field then return pretty_grad(field) end
	end
	do
		local field = is_face(name)
		if field then return pretty_face(field) end
	end
	do
		local U, p = is_mwi(name)
		if U then return pretty_mwi(U, p) end
	end
	do
		local field, comp = is_diag(name)
		if field then return pretty_diag(field, comp) end
	end
	do
		local U, p = is_div_mwi(name)
		if U then return pretty_div_mwi(U, p) end
	end
	do
		local field = is_div(name)
		if field then return pretty_div(field) end
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
		_pretty = function() return pretty_grad(field, i) end
	})
end

function M.diag(field, i)
	V.field_name(field, "E.diag field")
	assert(i == nil or i == "x" or i == "y",
		"Expr.diag: component (i) must be nil or 'x' or 'y'")

	return E.make_expr({
		kind = "diag",
		field = field,
		component = i,
		_dep_name = diag_name(field, i),
		_pretty = function() return pretty_diag(field, i) end
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
		_facewise = true,
		_pretty = function() return pretty_mwi(U_name, p_name) end
	})
end

function M.face(field)
	V.field_name(field, "face field")
	return E.make_expr {
		kind      = "face",
		field     = field,
		_dep_name = face_name(field),
		_facewise = true,
		_pretty   = function() return pretty_face(field) end
	}
end

function M.div(field)
	V.field_name(field, "div field")
	return E.make_expr({
		kind = "div",
		field = field,
		_dep_name = div_name(field),
		_pretty = function() return pretty_div(field) end
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
		_pretty = function() return pretty_div_mwi(U_name, p_name) end
	})
end

--
-- Helpers
--

local function is_facewise(e)
	return E.is_expr(e) and e._facewise
end

M.is_facewise = is_facewise

return M
