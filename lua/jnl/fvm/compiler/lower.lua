-- jnl/fvm/compiler/lower.lua - Concrete FVM instruction lowering
-- <jed@nelson.ac> // 2026-06-13
--
-- Converts abstract schedule ops (solve, evaluate, correct) into
-- concrete instruction sequences (sys_reset, lap_k, div_k, su_fs, ...).
--
-- div_cell substitution: when a laplacian coefficient contains a
-- divergence node, elab has pre-registered a __divcell_N cell field for
-- its value.  resolve_div_cells substitutes those divergence sub-trees
-- with synthetic symbol nodes pointing to the named cell field.  The
-- plain-table leaf { kind="symbol", name=..., rank=0 } works because
-- classify_coeff and Eval.compile only inspect .kind and .name.  Rebuilt
-- interior nodes carry the original Node metatable so Node.is_node passes.

local Node = require("jnl.nabla.node")
local Mangle = require("jnl.nabla.mangle")
local Inst = require("jnl.fvm.instruction")
local Elab = require("jnl.fvm.compiler.elab")

---@private
local M = {}

local AXES = { "x", "y" }

--
-- Name manglers (mirrored from elab.lua for local use)
--

local mangle_diag = Elab.mangle_diag
local mangle_facen_sym = Elab.mangle_facen_sym

--
-- Node helpers
--

local function neg_node(n)
	if n.kind == "constant" then return Node.const(-n.a) end
	if n.kind == "neg" then return n.a end
	return n:neg()
end

local function sign_node(n, s)
	return s == 1 and n or neg_node(n)
end

--
-- div_cell substitution
--
-- resolve_div_cells walks an expression tree and replaces any divergence
-- sub-node whose identity matches a registered div_cell entry with a
-- symbol leaf referencing the pre-computed __divcell_N field.
--

local function find_div_cell_for_node(node, elab)
	for dname, entry in pairs(elab.fields) do
		if entry.kind == "div_cell" and entry.div_node == node then
			return dname, entry
		end
	end
	return nil, nil
end

local function resolve_div_cells(node, elab)
	if not node or type(node) ~= "table" or not node.kind then return node end

	if node.kind == "divergence" then
		local dname = find_div_cell_for_node(node, elab)
		if dname then
			-- Synthetic symbol leaf: no Node metatable needed here because
			-- classify_coeff consumes it before any Node method is called.
			return { kind = "symbol", name = dname, rank = 0 }
		end
		return node
	end

	local new_a = node.a and resolve_div_cells(node.a, elab) or node.a
	local new_b = node.b and resolve_div_cells(node.b, elab) or node.b
	if new_a == node.a and new_b == node.b then return node end

	-- Rebuild with substituted children.  Copy the original metatable so
	-- Node.is_node() continues to return true on this reconstructed node.
	local syn = {}
	for k, v in pairs(node) do syn[k] = v end
	syn.a = new_a
	syn.b = new_b
	setmetatable(syn, getmetatable(node))
	return syn
end

--
-- Coefficient classification
--
-- Returns ("k", const_node), ("f", symbol_node), or ("expr", expr_node).
-- When elab is provided, divergence sub-trees are substituted first so
-- compound expressions like nu*div(U) resolve to "expr" over named fields.
--

local function classify_coeff(node, sign, elab)
	if node == nil then
		return "k", Node.const(sign == 1 and 1.0 or -1.0)
	end
	local n = sign_node(node, sign)
	if elab then n = resolve_div_cells(n, elab) end
	if n.kind == "constant" then return "k", n end
	if n.kind == "symbol" then return "f", n end
	return "expr", n
end

local function setup_coeff(out, ck, cn)
	if ck == "expr" then out[#out + 1] = Inst.eval_coeff(cn) end
end

--
-- Argument extraction
--

local function extract_scale(node, op)
	if node.kind == "symbol" then return nil, node end
	if node.kind == "scale" or node.kind == "mul" then return node.a, node.b end
	error("lower." .. op .. ": unexpected child kind '" .. node.kind .. "'", 2)
end

local function vec_comps(name, entry)
	return entry.components or { name .. "_x", name .. "_y" }
end

--
-- div_cell prereq emission
--
-- All registered div_cell intermediates are computed before sys_reset so
-- they are available as ordinary named cell fields during assembly.
--

local function emit_div_cell_inst(out, dname, entry, elab)
	local flux_entry = elab.face_flux[entry.flux_name]
	if entry.flux_kind == "symbol" and flux_entry and flux_entry.comps then
		out[#out + 1] = Inst.divergence_c(dname,
			flux_entry.comps[1], flux_entry.comps[2], true)
	elseif entry.flux_kind == "expr" and flux_entry then
		out[#out + 1] = Inst.eval_expr(flux_entry.vec_x,
			{ kind = "component", node = flux_entry.node, axis = "x" })
		out[#out + 1] = Inst.eval_expr(flux_entry.vec_y,
			{ kind = "component", node = flux_entry.node, axis = "y" })
		out[#out + 1] = Inst.divergence_c(dname,
			flux_entry.vec_x, flux_entry.vec_y, true)
	else
		error(string.format("div_cell: unsupported flux kind '%s' for '%s'",
			tostring(entry.flux_kind), dname))
	end
end

local function emit_div_cell_prereqs(out, elab)
	local names = {}
	for dname, entry in pairs(elab.fields) do
		if entry.kind == "div_cell" then names[#names + 1] = dname end
	end
	table.sort(names)
	for _, dname in ipairs(names) do
		emit_div_cell_inst(out, dname, elab.fields[dname], elab)
	end
end

--
-- face_normal_c prereq emission for bare div(symbol) in equations
--

local function collect_symbol_div_interps(node, elab, out, emitted)
	if not node or not Node.is_node(node) then return end
	if node.kind == "divergence" then
		local inner = node.a
		if inner.kind == "symbol" then
			local facen = mangle_facen_sym(inner.name)
			if not emitted[facen] then
				local fe = elab.face_flux[facen]
				if fe and fe.kind == "symbol" then
					out[#out + 1] = Inst.face_normal_c(fe.comps[1], fe.comps[2], facen)
					emitted[facen] = true
				end
			end
		end
	end
	collect_symbol_div_interps(node.a, elab, out, emitted)
	collect_symbol_div_interps(node.b, elab, out, emitted)
end

local function emit_symbol_div_interps(out, entry, elab)
	if not entry.equation then return end
	local emitted = {}
	collect_symbol_div_interps(entry.equation.lhs, elab, out, emitted)
	collect_symbol_div_interps(entry.equation.rhs, elab, out, emitted)
end

--
-- BC ghost fill emission
--

local function emit_ghost_fills_scalar(out, field, bcs)
	if not bcs then return end
	for _, bc in ipairs(bcs) do
		local k = bc.kind
		if k == "dirichlet_s" then
			out[#out + 1] = Inst.pfill_s_d(field, bc.patch, bc.value)
		elseif k == "neumann_s" then
			out[#out + 1] = Inst.pfill_s_n(field, bc.patch, bc.grad_n)
		elseif k == "robin_s" then
			out[#out + 1] = Inst.pfill_s_r(field, bc.patch, bc.a, bc.b, bc.c)
		end
	end
end

local function emit_ghost_fills_vector(out, ux, uy, bcs)
	if not bcs then return end
	for _, bc in ipairs(bcs) do
		local k = bc.kind
		if k == "dirichlet_v" then
			out[#out + 1] = Inst.pfill_v_d(ux, uy, bc.patch, bc.ux, bc.uy)
		elseif k == "neumann_v" then
			out[#out + 1] = Inst.pfill_v_n(ux, uy, bc.patch, bc.ux_gn, bc.uy_gn)
		elseif k == "nt_v" then
			out[#out + 1] = Inst.pfill_v_nt(ux, uy, bc.patch, bc.nkind, bc.nval, bc.tkind, bc.tval)
		end
	end
end

local function emit_bc_close_scalar(out, field, bcs)
	if not bcs then return end
	for _, bc in ipairs(bcs) do
		local k = bc.kind
		if k == "dirichlet_s" then
			out[#out + 1] = Inst.pclose_s_d(field, bc.patch, bc.value)
		elseif k == "neumann_s" then
			out[#out + 1] = Inst.pclose_s_n(field, bc.patch, bc.grad_n)
		elseif k == "robin_s" then
			out[#out + 1] = Inst.pclose_s_r(field, bc.patch, bc.a, bc.b, bc.c)
		end
	end
end

--
-- Component-level operator emitters
--

local function emit_ddt_comp(out, comp, rho_node, sign, elab)
	local ck, cn = classify_coeff(rho_node, sign, elab)
	setup_coeff(out, ck, cn)
	if ck == "k" then
		out[#out + 1] = Inst.ddt_k(comp, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.ddt_f(comp, cn.name, cn)
	else
		out[#out + 1] = Inst.ddt_f(comp, "__coeff", cn)
	end
end

local function emit_lap_comp(out, comp, coeff_node, sign, elab)
	local ck, cn = classify_coeff(coeff_node, sign, elab)
	local gx, gy = Mangle.grad(comp, "x"), Mangle.grad(comp, "y")
	setup_coeff(out, ck, cn)
	if ck == "k" then
		out[#out + 1] = Inst.lap_k(comp, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.lap_f(comp, cn.name, cn)
	else
		out[#out + 1] = Inst.lap_f(comp, "__coeff", cn)
	end
	if ck == "expr" then out[#out + 1] = Inst.eval_coeff(cn) end
	if ck == "k" then
		out[#out + 1] = Inst.lap_nonorth_k(comp, gx, gy, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.lap_nonorth_f(comp, gx, gy, cn.name, cn)
	else
		out[#out + 1] = Inst.lap_nonorth_f(comp, gx, gy, "__coeff", cn)
	end
end

local function emit_div_comp(out, comp, flux_name, rho_node, sign, elab)
	local ck, cn = classify_coeff(rho_node, sign, elab)
	setup_coeff(out, ck, cn)
	if ck == "k" then
		out[#out + 1] = Inst.div_k(comp, flux_name, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.div_f(comp, flux_name, cn.name, cn)
	else
		out[#out + 1] = Inst.div_f(comp, flux_name, "__coeff", cn)
	end
	out[#out + 1] = Inst.div_dc(comp, flux_name,
		Mangle.grad(comp, "x"), Mangle.grad(comp, "y"))
end

--
-- Explicit source emitters
--

local function emit_su_field_comp(out, comp, src_name, sign, display_node)
	out[#out + 1] = Inst.su_fs(comp, -sign, src_name, true, display_node)
end

local function emit_su_const_comp(out, comp, value, sign)
	if value == 0 then return end
	out[#out + 1] = Inst.su_k(comp, -sign * value, true)
end

local function emit_su_div_coeff(out, comp, div_node, sign)
	out[#out + 1] = Inst.eval_coeff(div_node)
	out[#out + 1] = Inst.su_fs(comp, -sign, "__coeff", false, div_node)
end

--
-- Equation walkers
-- Forward declarations needed for mutually recursive add/sub handlers.
--

local walk_scalar_node
local walk_vector_node

local walk_scalar = {}

walk_scalar.add = function(out, node, field, sign, elab)
	walk_scalar_node(out, node.a, field, sign, elab)
	walk_scalar_node(out, node.b, field, sign, elab)
end
walk_scalar.sub = function(out, node, field, sign, elab)
	walk_scalar_node(out, node.a, field, sign, elab)
	walk_scalar_node(out, node.b, field, -sign, elab)
end
walk_scalar.neg = function(out, node, field, sign, elab)
	walk_scalar_node(out, node.a, field, -sign, elab)
end

walk_scalar.ddt = function(out, node, field, sign, elab)
	local rho, phi = extract_scale(node.a, "ddt")
	if phi.name ~= field then return end
	emit_ddt_comp(out, field, rho, sign, elab)
end

walk_scalar.laplacian = function(out, node, field, sign, elab)
	local coeff, phi = extract_scale(node.a, "laplacian")
	if phi.name ~= field then return end
	emit_lap_comp(out, field, coeff, sign, elab)
end

walk_scalar.divergence = function(out, node, field, sign, elab)
	local inner = node.a
	if inner.kind == "scale" and inner.b.kind == "mwi" and inner.a.name == field then
		emit_div_comp(out, field, Mangle.accessor("mwi", inner.b), nil, sign, elab)
		return
	end
	if inner.kind == "mwi" then
		emit_su_div_coeff(out, field, node, sign)
		return
	end
	if inner.kind == "symbol" then
		local facen = mangle_facen_sym(inner.name)
		out[#out + 1] = Inst.su_fs(field, -sign, facen, false, node)
		return
	end
end

walk_scalar.symbol = function(out, node, field, sign, _)
	if node.name == field then return end
	emit_su_field_comp(out, field, node.name, sign, node)
end

walk_scalar.constant = function(out, node, field, sign, _)
	emit_su_const_comp(out, field, node.a, sign)
end

walk_scalar.mwi = function() end
walk_scalar.accessor = function() end
walk_scalar.grad = function() end

local walk_vector = {}

walk_vector.add = function(out, node, field, comps, sign, elab)
	walk_vector_node(out, node.a, field, comps, sign, elab)
	walk_vector_node(out, node.b, field, comps, sign, elab)
end

walk_vector.sub = function(out, node, field, comps, sign, elab)
	walk_vector_node(out, node.a, field, comps, sign, elab)
	walk_vector_node(out, node.b, field, comps, -sign, elab)
end

walk_vector.neg = function(out, node, field, comps, sign, elab)
	walk_vector_node(out, node.a, field, comps, -sign, elab)
end

walk_vector.ddt = function(out, node, _, comps, sign, elab)
	local rho, _ = extract_scale(node.a, "ddt")
	for _, comp in ipairs(comps) do emit_ddt_comp(out, comp, rho, sign, elab) end
end

walk_vector.laplacian = function(out, node, _, comps, sign, elab)
	local coeff, _ = extract_scale(node.a, "laplacian")
	for _, comp in ipairs(comps) do emit_lap_comp(out, comp, coeff, sign, elab) end
end

walk_vector.divergence = function(out, node, _, comps, sign, elab)
	local inner = node.a
	if inner.kind == "outer" then
		local flux_node = inner.a.kind == "mwi" and inner.a or inner.b
		local flux      = Mangle.accessor("mwi", flux_node)
		for _, comp in ipairs(comps) do
			emit_div_comp(out, comp, flux, nil, sign, elab)
		end
		return
	end
end

walk_vector.grad = function(out, node, _, comps, sign, _)
	local scalar = node.a
	assert(scalar.rank == 0 and scalar.name,
		"lower: grad source in vector equation has no named scalar")
	for i, comp in ipairs(comps) do
		emit_su_field_comp(out, comp, Mangle.grad(scalar.name, AXES[i]), sign, node)
	end
end

walk_vector.cvec = function(out, node, _, comps, sign, _)
	for i, comp in ipairs(comps) do
		emit_su_const_comp(out, comp, node.a and node.a[i] or 0, sign)
	end
end

walk_vector.constant = function(out, node, _, comps, sign, _)
	for _, comp in ipairs(comps) do emit_su_const_comp(out, comp, node.a, sign) end
end

walk_scalar_node = function(out, node, field, sign, elab)
	if not node then return end
	local fn = walk_scalar[node.kind]
	if fn then
		fn(out, node, field, sign, elab)
	else
		out[#out + 1] = Inst.new("comment",
			{ text = "lower: unhandled scalar node '" .. tostring(node.kind) .. "'" })
	end
end

walk_vector_node = function(out, node, field, comps, sign, elab)
	if not node then return end
	local fn = walk_vector[node.kind]
	if fn then
		fn(out, node, field, comps, sign, elab)
	else
		out[#out + 1] = Inst.new("comment",
			{ text = "lower: unhandled vector node '" .. tostring(node.kind) .. "'" })
	end
end

--
-- Solve expansion
--

local function expand_solve_scalar(out, field, entry, elab)
	emit_ghost_fills_scalar(out, field, entry.bcs)
	emit_symbol_div_interps(out, entry, elab)
	emit_div_cell_prereqs(out, elab)
	out[#out + 1] = Inst.sys_reset(field)
	walk_scalar_node(out, entry.equation.lhs, field, 1, elab)
	walk_scalar_node(out, entry.equation.rhs, field, -1, elab)
	emit_bc_close_scalar(out, field, entry.bcs)
	if elab.fields[mangle_diag(field)] then
		out[#out + 1] = Inst.diag_snapshot(field, mangle_diag(field))
	end
end

local function expand_solve_vector(out, field, entry, elab)
	local comps  = vec_comps(field, entry)
	local ux, uy = comps[1], comps[2]
	emit_ghost_fills_vector(out, ux, uy, entry.bcs)
	emit_div_cell_prereqs(out, elab)
	for _, comp in ipairs(comps) do out[#out + 1] = Inst.sys_reset(comp) end
	walk_vector_node(out, entry.equation.lhs, field, comps, 1, elab)
	walk_vector_node(out, entry.equation.rhs, field, comps, -1, elab)
	for _, comp in ipairs(comps) do
		if elab.fields[mangle_diag(comp)] then
			out[#out + 1] = Inst.diag_snapshot(comp, mangle_diag(comp))
		end
	end
end

local function emit_solve_linalg(out, field, entry)
	if entry.rank == 0 then
		out[#out + 1] = Inst.under_relax(field)
		out[#out + 1] = Inst.solve_linalg(field)
		return
	end
	for _, comp in ipairs(vec_comps(field, entry)) do
		out[#out + 1] = Inst.under_relax(comp)
		out[#out + 1] = Inst.solve_linalg(comp)
	end
end

--
-- Abstract -> concrete dispatch
--

local abstract_expand = {}

abstract_expand.solve = function(inst, reg, elab)
	local field = inst.field
	local entry = reg:entry(field)
	local out   = {}
	if entry.rank == 0 then
		expand_solve_scalar(out, field, entry, elab)
	elseif entry.rank == 1 then
		expand_solve_vector(out, field, entry, elab)
	else
		error("lower: rank-" .. tostring(entry.rank)
			.. " solve not supported for field '" .. field .. "'")
	end
	emit_solve_linalg(out, field, entry)
	return out
end

abstract_expand.evaluate = function(inst, reg, _)
	local entry = reg:entry(inst.field)
	if not entry or not entry.expr then return {} end
	return { Inst.eval_expr(inst.field, entry.expr) }
end

abstract_expand.correct = function(inst, reg, _)
	local entry = reg:entry(inst.field)
	if not entry or not entry.correction then return {} end
	return { Inst.apply_correction(inst.field, entry.correction) }
end

abstract_expand.inner = function(inst, reg, elab)
	local inner = inst.fields and inst.fields.alg
	if inner then M._lower_alg(inner, reg, elab) end
	return { inst }
end

local function lower_phase(phase, reg, elab)
	local out = {}
	for _, inst in ipairs(phase) do
		local fn = abstract_expand[inst.op]
		if fn then
			local concrete = fn(inst, reg, elab)
			for _, ci in ipairs(concrete) do out[#out + 1] = ci end
		else
			out[#out + 1] = inst
		end
	end
	return out
end

-- Stored as M._lower_alg so the inner handler above can call it recursively.
function M._lower_alg(alg, reg, elab)
	alg.pre  = lower_phase(alg.pre or {}, reg, elab)
	alg.main = lower_phase(alg.main or {}, reg, elab)
	alg.post = lower_phase(alg.post or {}, reg, elab)
end

--
-- Public
--

--- Lower the abstract schedule in alg to concrete FVM assembly instructions.
---@param alg Algorithm
---@param reg Registry
function M.lower(alg, reg)
	local elab = alg.elaborated
	assert(elab, "lower: alg.elaborated is nil -- run elaborate() first")
	M._lower_alg(alg, reg, elab)
end

--- Lower a single field equation to a concrete instruction list.
---
--- Useful for inspecting the assembly of one equation in isolation.
--- The returned info table contains lightweight summary flags so callers
--- can write assertions without reimplementing instruction walks.
---
---@param field  string
---@param entry  table   Registry entry with .equation, .rank, .bcs.
---@param elab   table   Elaboration result (alg.elaborated).
---@return Inst[] instructions
---@return table  info   { has_div_cells, has_ghost_fills, n_instructions }
function M.lower_equation(field, entry, elab)
	assert(entry.equation, "lower_equation: entry '" .. field .. "' has no equation")
	local out = {}
	if entry.rank == 0 then
		expand_solve_scalar(out, field, entry, elab)
	elseif entry.rank == 1 then
		expand_solve_vector(out, field, entry, elab)
	else
		error("lower_equation: rank-" .. tostring(entry.rank) .. " not supported")
	end
	emit_solve_linalg(out, field, entry)

	local has_div_cells   = false
	local has_ghost_fills = false
	for _, inst in ipairs(out) do
		if inst.op == "divergence_c" then has_div_cells = true end
		if inst.op:find("^patch_") then has_ghost_fills = true end
	end

	return out, {
		has_div_cells   = has_div_cells,
		has_ghost_fills = has_ghost_fills,
		n_instructions  = #out,
	}
end

return M
