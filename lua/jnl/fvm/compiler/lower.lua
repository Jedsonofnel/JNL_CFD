-- jnl/fvm/compiler/lower.lua - Concrete FVM instruction lowering
-- <jed@nelson.ac> // 2026-06-13
--
-- Converts abstract schedule ops (solve, evaluate, correct) into
-- concrete instruction sequences (sys_reset, lap_k, div_k, su_fs, ...).

local Node = require("jnl.nabla.node")
local Resolve = require("jnl.nabla.resolve")
local Mangle = require("jnl.nabla.mangle")
local Inst = require("jnl.fvm.instruction")
local Elab = require("jnl.fvm.compiler.elab")

---@private
local M = {}

--
-- Axes / dimensions
--

local function normalise_ndims(ndims)
	ndims = ndims or 2
	assert(ndims == 2 or ndims == 3,
		"lower: ndims must be 2 or 3, got " .. tostring(ndims))
	return ndims
end

local function axes_for(ndims)
	local axes = {}
	for i = 1, ndims do
		axes[i] = Node.AXES[i]
	end
	return axes
end

local function make_ctx(reg, elab, ndims)
	ndims = normalise_ndims(ndims)
	return {
		reg   = reg,
		elab  = elab or { fields = {}, face_flux = {} },
		ndims = ndims,
		axes  = axes_for(ndims),
	}
end

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

local function rebuild_node(node, new_a, new_b)
	local syn = {}
	for k, v in pairs(node) do syn[k] = v end
	syn.a = new_a
	syn.b = new_b
	setmetatable(syn, getmetatable(node))
	return syn
end

local function internal_sym(name)
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = 0,
	}, Node)
end

local function emit_section(out, text)
	out[#out + 1] = Inst.section(text)
end

--
-- div_cell substitution
--

local function find_div_cell_for_node(node, ctx)
	local elab = ctx and ctx.elab
	if not elab then return nil, nil end

	for dname, entry in pairs(elab.fields or {}) do
		if entry.kind == "div_cell" and entry.div_node == node then
			return dname, entry
		end
	end
	return nil, nil
end

local function resolve_div_cells(node, ctx)
	if not node or type(node) ~= "table" or not node.kind then return node end

	if node.kind == "divergence" then
		local dname = find_div_cell_for_node(node, ctx)
		if dname then return internal_sym(dname) end
		return node
	end

	local new_a = node.a and resolve_div_cells(node.a, ctx) or node.a
	local new_b = node.b and resolve_div_cells(node.b, ctx) or node.b
	if new_a == node.a and new_b == node.b then return node end

	return rebuild_node(node, new_a, new_b)
end

--
-- Coefficient classification
--
-- Returns ("k", const_node), ("f", symbol_node), or ("expr", expr_node).
-- When ctx is provided, divergence sub-trees are substituted first so
-- compound expressions like nu*div(U) resolve to "expr" over named fields.
--

local function classify_coeff(node, sign, ctx)
	if node == nil then
		return "k", Node.const(sign == 1 and 1.0 or -1.0)
	end

	local n = sign_node(node, sign)
	if ctx then n = resolve_div_cells(n, ctx) end

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

local function vec_comps(ctx, name, entry)
	if entry.components then return entry.components end

	local comps = {}
	for i, ax in ipairs(ctx.axes) do
		comps[i] = Mangle.field(name, ax)
	end
	return comps
end

local function grad_names(ctx, field)
	local names = {}
	for i, ax in ipairs(ctx.axes) do
		names[i] = Mangle.grad(field, ax)
	end
	return names
end

local function grad_inst(ctx, field)
	local g = grad_names(ctx, field)
	local inst = Inst.grad(field, g[1], g[2])

	-- Future-proof for 3D display/dispatch. Current Inst.grad and dispatch
	-- consume out_x/out_y only, so this is harmless in 2D.
	if ctx.ndims == 3 then inst.out_z = g[3] end

	return inst
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

local function emit_ghost_fills_vector(out, comps, bcs)
	if not bcs then return end

	local ux, uy = comps[1], comps[2]
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
-- Explicit eval/correct scalarisation
--
-- Eval.compile is scalar-only.  Abstract evaluate/correct ops may target
-- vector fields, so lower resolves them to component scalar expressions.
--
-- resolve.lua is responsible for erasing tensor structure, including turning
-- grad(phi)_x into ordinary scalar symbols such as grad_phi_x.  The compiler
-- only needs to ensure those gradient fields are freshly computed before an
-- eval_expr/apply_correction instruction reads them.
--

local function resolve_eval_scalar(ctx, node)
	local r = Resolve.resolve(node, ctx.ndims)
	r = resolve_div_cells(r, ctx)

	assert(Node.is_node(r),
		"lower: scalar expression did not resolve to a Node")
	assert(r.rank == 0,
		"lower: scalar expression resolved to rank-" .. tostring(r.rank))

	return r
end

local function resolve_eval_components(ctx, node)
	local r = Resolve.resolve(node, ctx.ndims)
	assert(type(r) == "table" and not Node.is_node(r),
		"lower: vector expression did not resolve to component list")

	for i, n in ipairs(r) do
		r[i] = resolve_div_cells(n, ctx)
		assert(Node.is_node(r[i]),
			"lower: component " .. i .. " did not resolve to a Node")
		assert(r[i].rank == 0,
			"lower: component " .. i .. " resolved to rank-" .. tostring(r[i].rank))
	end

	return r
end

local function collect_grad_symbols(node, ctx, out)
	if not node or not Node.is_node(node) then return end

	if node.kind == "symbol" and node.name then
		local ge = ctx.elab.fields and ctx.elab.fields[node.name]
		if ge and ge.kind == "grad" and ge.source then
			out[ge.source] = true
		end
	end

	collect_grad_symbols(node.a, ctx, out)
	collect_grad_symbols(node.b, ctx, out)
end

local function emit_grad_source(out, source, ctx, emitted)
	if emitted[source] then return end

	local entry = ctx.reg and ctx.reg:entry(source)
	if entry and entry.rank == 0 then
		-- Gradients use ghost values, so refresh scalar patch ghosts after
		-- the source may have changed.
		emit_ghost_fills_scalar(out, source, entry.bcs)
	end

	out[#out + 1] = grad_inst(ctx, source)
	emitted[source] = true
end

local function emit_grad_prereqs(out, node, ctx, emitted)
	local sources = {}
	collect_grad_symbols(node, ctx, sources)

	local names = {}
	for source in pairs(sources) do names[#names + 1] = source end
	table.sort(names)

	for _, source in ipairs(names) do
		emit_grad_source(out, source, ctx, emitted)
	end
end

local function emit_eval_scalar(out, field, node, ctx, emitted_grad)
	assert(Node.is_node(node),
		"lower: eval scalar for '" .. tostring(field) .. "' is not a Node")
	assert(node.rank == 0,
		"lower: eval scalar for '" .. tostring(field)
		.. "' is rank-" .. tostring(node.rank))

	emit_grad_prereqs(out, node, ctx, emitted_grad)
	out[#out + 1] = Inst.eval_expr(field, node)
end

local function emit_correct_scalar(out, field, node, ctx, emitted_grad)
	assert(Node.is_node(node),
		"lower: correction scalar for '" .. tostring(field) .. "' is not a Node")
	assert(node.rank == 0,
		"lower: correction scalar for '" .. tostring(field)
		.. "' is rank-" .. tostring(node.rank))

	emit_grad_prereqs(out, node, ctx, emitted_grad)
	out[#out + 1] = Inst.apply_correction(field, node)
end

--
-- div_cell prereq emission
--
-- All registered div_cell intermediates are computed before sys_reset/eval so
-- they are available as ordinary named cell fields during assembly.
--

local function emit_div_cell_inst(out, dname, entry, ctx)
	local flux_entry = ctx.elab.face_flux[entry.flux_name]

	if entry.flux_kind == "symbol" and flux_entry and flux_entry.comps then
		local inst = Inst.divergence_c(dname,
			flux_entry.comps[1], flux_entry.comps[2], true)
		if ctx.ndims == 3 then inst.uz = flux_entry.comps[3] end
		out[#out + 1] = inst
	elseif entry.flux_kind == "expr" and flux_entry then
		local nodes = resolve_eval_components(ctx, flux_entry.node)
		local emitted_grad = {}

		emit_eval_scalar(out, flux_entry.vec_x, nodes[1], ctx, emitted_grad)
		emit_eval_scalar(out, flux_entry.vec_y, nodes[2], ctx, emitted_grad)

		local inst = Inst.divergence_c(dname,
			flux_entry.vec_x, flux_entry.vec_y, true)
		if ctx.ndims == 3 then inst.uz = flux_entry.vec_z end
		out[#out + 1] = inst
	else
		error(string.format("div_cell: unsupported flux kind '%s' for '%s'",
			tostring(entry.flux_kind), dname))
	end
end

local function emit_div_cell_prereqs(out, ctx)
	local names = {}
	for dname, entry in pairs(ctx.elab.fields or {}) do
		if entry.kind == "div_cell" then names[#names + 1] = dname end
	end
	table.sort(names)

	for _, dname in ipairs(names) do
		emit_div_cell_inst(out, dname, ctx.elab.fields[dname], ctx)
	end
end

--
-- face_normal_c prereq emission for bare div(symbol) in equations
--

local function collect_symbol_div_interps(node, ctx, out, emitted)
	if not node or not Node.is_node(node) then return end

	if node.kind == "divergence" then
		local inner = node.a
		if inner.kind == "symbol" then
			local facen = mangle_facen_sym(inner.name)
			if not emitted[facen] then
				local fe = ctx.elab.face_flux[facen]
				if fe and fe.kind == "symbol" then
					local inst = Inst.face_normal_c(fe.comps[1], fe.comps[2], facen)
					if ctx.ndims == 3 then inst.uz = fe.comps[3] end
					out[#out + 1] = inst
					emitted[facen] = true
				end
			end
		end
	end

	collect_symbol_div_interps(node.a, ctx, out, emitted)
	collect_symbol_div_interps(node.b, ctx, out, emitted)
end

local function emit_symbol_div_interps(out, entry, ctx)
	if not entry.equation then return end

	local emitted = {}
	collect_symbol_div_interps(entry.equation.lhs, ctx, out, emitted)
	collect_symbol_div_interps(entry.equation.rhs, ctx, out, emitted)
end

--
-- Component-level operator emitters
--

local function emit_ddt_comp(out, comp, rho_node, sign, ctx)
	local ck, cn = classify_coeff(rho_node, sign, ctx)
	setup_coeff(out, ck, cn)

	if ck == "k" then
		out[#out + 1] = Inst.ddt_k(comp, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.ddt_f(comp, cn.name, cn)
	else
		out[#out + 1] = Inst.ddt_f(comp, "__coeff", cn)
	end
end

local function emit_lap_comp(out, comp, coeff_node, sign, ctx)
	local ck, cn = classify_coeff(coeff_node, sign, ctx)
	local g = grad_names(ctx, comp)

	setup_coeff(out, ck, cn)

	if ck == "k" then
		out[#out + 1] = Inst.lap_k(comp, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.lap_f(comp, cn.name, cn)
	else
		out[#out + 1] = Inst.lap_f(comp, "__coeff", cn)
	end

	-- Non-orthogonal correction uses the current gradient of the solved
	-- field.  Runtime config can still make lap_nonorth_* a no-op.
	out[#out + 1] = grad_inst(ctx, comp)

	if ck == "expr" then out[#out + 1] = Inst.eval_coeff(cn) end

	if ck == "k" then
		out[#out + 1] = Inst.lap_nonorth_k(comp, g[1], g[2], cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.lap_nonorth_f(comp, g[1], g[2], cn.name, cn)
	else
		out[#out + 1] = Inst.lap_nonorth_f(comp, g[1], g[2], "__coeff", cn)
	end
end

local function emit_div_comp(out, comp, flux_name, rho_node, sign, ctx)
	local ck, cn = classify_coeff(rho_node, sign, ctx)
	setup_coeff(out, ck, cn)

	if ck == "k" then
		out[#out + 1] = Inst.div_k(comp, flux_name, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.div_f(comp, flux_name, cn.name, cn)
	else
		out[#out + 1] = Inst.div_f(comp, flux_name, "__coeff", cn)
	end

	local g = grad_names(ctx, comp)
	out[#out + 1] = Inst.div_dc(comp, flux_name, g[1], g[2])
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
	local mwi_name = Mangle.accessor("mwi", div_node.a)
	local tmp_name = "__mwidiv_" .. mwi_name
	out[#out + 1] = Inst.divergence(mwi_name, tmp_name)
	out[#out + 1] = Inst.su_fs(comp, -sign, tmp_name, false, div_node)
end

--
-- Equation walkers
-- Forward declarations needed for mutually recursive add/sub handlers.
--

local walk_scalar_node
local walk_vector_node

local walk_scalar = {}

walk_scalar.add = function(out, node, field, sign, ctx)
	walk_scalar_node(out, node.a, field, sign, ctx)
	walk_scalar_node(out, node.b, field, sign, ctx)
end

walk_scalar.sub = function(out, node, field, sign, ctx)
	walk_scalar_node(out, node.a, field, sign, ctx)
	walk_scalar_node(out, node.b, field, -sign, ctx)
end

walk_scalar.neg = function(out, node, field, sign, ctx)
	walk_scalar_node(out, node.a, field, -sign, ctx)
end

walk_scalar.ddt = function(out, node, field, sign, ctx)
	local rho, phi = extract_scale(node.a, "ddt")
	if phi.name ~= field then return end
	emit_ddt_comp(out, field, rho, sign, ctx)
end

walk_scalar.laplacian = function(out, node, field, sign, ctx)
	local coeff, phi = extract_scale(node.a, "laplacian")
	if phi.name ~= field then return end
	emit_lap_comp(out, field, coeff, sign, ctx)
end

walk_scalar.divergence = function(out, node, field, sign, ctx)
	local inner = node.a

	if inner.kind == "scale" and inner.b.kind == "mwi" and inner.a.name == field then
		emit_div_comp(out, field, Mangle.accessor("mwi", inner.b), nil, sign, ctx)
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

walk_vector.add = function(out, node, field, comps, sign, ctx)
	walk_vector_node(out, node.a, field, comps, sign, ctx)
	walk_vector_node(out, node.b, field, comps, sign, ctx)
end

walk_vector.sub = function(out, node, field, comps, sign, ctx)
	walk_vector_node(out, node.a, field, comps, sign, ctx)
	walk_vector_node(out, node.b, field, comps, -sign, ctx)
end

walk_vector.neg = function(out, node, field, comps, sign, ctx)
	walk_vector_node(out, node.a, field, comps, -sign, ctx)
end

walk_vector.ddt = function(out, node, _, comps, sign, ctx)
	local rho, _ = extract_scale(node.a, "ddt")
	for _, comp in ipairs(comps) do
		emit_ddt_comp(out, comp, rho, sign, ctx)
	end
end

walk_vector.laplacian = function(out, node, _, comps, sign, ctx)
	local coeff, _ = extract_scale(node.a, "laplacian")
	for _, comp in ipairs(comps) do
		emit_lap_comp(out, comp, coeff, sign, ctx)
	end
end

walk_vector.divergence = function(out, node, _, comps, sign, ctx)
	local inner = node.a
	if inner.kind == "outer" then
		local flux_node = inner.a.kind == "mwi" and inner.a or inner.b
		local flux = Mangle.accessor("mwi", flux_node)
		for _, comp in ipairs(comps) do
			emit_div_comp(out, comp, flux, nil, sign, ctx)
		end
		return
	end
end

walk_vector.grad = function(out, node, _, comps, sign, ctx)
	local scalar = node.a
	assert(scalar.rank == 0 and scalar.name,
		"lower: grad source in vector equation has no named scalar")

	local emitted = {}
	emit_grad_source(out, scalar.name, ctx, emitted)

	for i, comp in ipairs(comps) do
		emit_su_field_comp(out, comp,
			Mangle.grad(scalar.name, ctx.axes[i]), sign, node)
	end
end

walk_vector.cvec = function(out, node, _, comps, sign, _)
	for i, comp in ipairs(comps) do
		emit_su_const_comp(out, comp, node.a and node.a[i] or 0, sign)
	end
end

walk_vector.constant = function(out, node, _, comps, sign, _)
	for _, comp in ipairs(comps) do
		emit_su_const_comp(out, comp, node.a, sign)
	end
end

walk_scalar_node = function(out, node, field, sign, ctx)
	if not node then return end

	local fn = walk_scalar[node.kind]
	if fn then
		fn(out, node, field, sign, ctx)
	else
		out[#out + 1] = Inst.new("comment",
			{ text = "lower: unhandled scalar node '" .. tostring(node.kind) .. "'" })
	end
end

walk_vector_node = function(out, node, field, comps, sign, ctx)
	if not node then return end

	local fn = walk_vector[node.kind]
	if fn then
		fn(out, node, field, comps, sign, ctx)
	else
		out[#out + 1] = Inst.new("comment",
			{ text = "lower: unhandled vector node '" .. tostring(node.kind) .. "'" })
	end
end

--
-- Solve expansion
--

local function expand_solve_scalar(out, field, entry, ctx)
	emit_ghost_fills_scalar(out, field, entry.bcs)
	emit_symbol_div_interps(out, entry, ctx)
	emit_div_cell_prereqs(out, ctx)

	out[#out + 1] = Inst.sys_reset(field)

	walk_scalar_node(out, entry.equation.lhs, field, 1, ctx)
	walk_scalar_node(out, entry.equation.rhs, field, -1, ctx)

	emit_bc_close_scalar(out, field, entry.bcs)

	if ctx.elab.fields[mangle_diag(field)] then
		out[#out + 1] = Inst.diag_snapshot(field, mangle_diag(field))
	end
end

local function expand_solve_vector(out, field, entry, ctx)
	local comps = vec_comps(ctx, field, entry)

	emit_ghost_fills_vector(out, comps, entry.bcs)
	emit_div_cell_prereqs(out, ctx)

	for _, comp in ipairs(comps) do
		out[#out + 1] = Inst.sys_reset(comp)
	end

	walk_vector_node(out, entry.equation.lhs, field, comps, 1, ctx)
	walk_vector_node(out, entry.equation.rhs, field, comps, -1, ctx)

	for _, comp in ipairs(comps) do
		if ctx.elab.fields[mangle_diag(comp)] then
			out[#out + 1] = Inst.diag_snapshot(comp, mangle_diag(comp))
		end
	end
end

local function emit_solve_linalg(out, field, entry, ctx)
	if entry.rank == 0 then
		out[#out + 1] = Inst.under_relax(field)
		out[#out + 1] = Inst.solve_linalg(field)
		return
	end

	for _, comp in ipairs(vec_comps(ctx, field, entry)) do
		out[#out + 1] = Inst.under_relax(comp)
		out[#out + 1] = Inst.solve_linalg(comp)
	end
end

--
-- Abstract eval/correct expansion
--

local function expand_eval_expr(out, field, entry, ctx)
	emit_div_cell_prereqs(out, ctx)

	if entry.rank == 0 then
		local node = resolve_eval_scalar(ctx, entry.expr)
		emit_eval_scalar(out, field, node, ctx, {})
		return
	end

	if entry.rank == 1 then
		local comps = vec_comps(ctx, field, entry)
		local nodes = resolve_eval_components(ctx, entry.expr)
		local emitted_grad = {}

		for i, comp in ipairs(comps) do
			emit_eval_scalar(out, comp, nodes[i], ctx, emitted_grad)
		end
		return
	end

	error("lower: evaluate rank-" .. tostring(entry.rank)
		.. " not supported for field '" .. tostring(field) .. "'")
end

local function expand_apply_correction(out, field, entry, ctx)
	emit_div_cell_prereqs(out, ctx)

	if entry.rank == 0 then
		local node = resolve_eval_scalar(ctx, entry.correction)
		emit_correct_scalar(out, field, node, ctx, {})
		return
	end

	if entry.rank == 1 then
		local comps = vec_comps(ctx, field, entry)
		local nodes = resolve_eval_components(ctx, entry.correction)
		local emitted_grad = {}

		for i, comp in ipairs(comps) do
			emit_correct_scalar(out, comp, nodes[i], ctx, emitted_grad)
		end
		return
	end

	error("lower: correct rank-" .. tostring(entry.rank)
		.. " not supported for field '" .. tostring(field) .. "'")
end

--
-- Abstract -> concrete dispatch
--

local abstract_expand = {}

abstract_expand.solve = function(inst, ctx)
	local field = inst.field
	local entry = ctx.reg:entry(field)
	local out = {}

	emit_section(out, "SOLVE " .. field)

	if entry.rank == 0 then
		expand_solve_scalar(out, field, entry, ctx)
	elseif entry.rank == 1 then
		expand_solve_vector(out, field, entry, ctx)
	else
		error("lower: rank-" .. tostring(entry.rank)
			.. " solve not supported for field '" .. field .. "'")
	end

	emit_solve_linalg(out, field, entry, ctx)
	return out
end

abstract_expand.evaluate = function(inst, ctx)
	local entry = ctx.reg:entry(inst.field)
	if not entry or not entry.expr then return {} end

	local out = {}
	if inst.implicit == false then
		emit_section(out, "EVALUATE " .. inst.field)
	end
	expand_eval_expr(out, inst.field, entry, ctx)
	return out
end

abstract_expand.correct = function(inst, ctx)
	local entry = ctx.reg:entry(inst.field)
	if not entry or not entry.correction then return {} end

	local out = {}
	emit_section(out, "CORRECT " .. inst.field)
	expand_apply_correction(out, inst.field, entry, ctx)
	return out
end

abstract_expand.inner = function(inst, ctx)
	local inner = inst.fields and inst.fields.alg
	if inner then M._lower_alg(inner, ctx) end
	return { inst }
end

local function lower_phase(phase, ctx)
	local out = {}

	for _, inst in ipairs(phase) do
		local fn = abstract_expand[inst.op]
		if fn then
			local concrete = fn(inst, ctx)
			for _, ci in ipairs(concrete) do out[#out + 1] = ci end
		else
			out[#out + 1] = inst
		end
	end

	return out
end

-- Stored as M._lower_alg so the inner handler above can call it recursively.
function M._lower_alg(alg, ctx)
	alg.pre  = lower_phase(alg.pre or {}, ctx)
	alg.main = lower_phase(alg.main or {}, ctx)
	alg.post = lower_phase(alg.post or {}, ctx)
end

--
-- Public
--

--- Lower the abstract schedule in alg to concrete FVM assembly instructions.
---@param alg Algorithm
---@param reg Registry
---@param ndims integer? Number of spatial dimensions. Defaults to 2.
function M.lower(alg, reg, ndims)
	local elab = alg.elaborated
	assert(elab, "lower: alg.elaborated is nil -- run elaborate() first")

	local ctx = make_ctx(reg, elab, ndims)
	alg.ndims = ctx.ndims

	M._lower_alg(alg, ctx)
end

--- Lower a single field equation to a concrete instruction list.
---
--- Useful for inspecting the assembly of one equation in isolation.
--- The returned info table contains lightweight summary flags so callers
--- can write assertions without reimplementing instruction walks.
---
---@param field  string
---@param entry  table    Registry entry with .equation, .rank, .bcs.
---@param elab   table    Elaboration result (alg.elaborated).
---@param ndims  integer? Number of spatial dimensions. Defaults to 2.
---@param reg    table?   Optional registry, used for gradient ghost refresh.
---@return Inst[] instructions
---@return table  info   { has_div_cells, has_ghost_fills, n_instructions }
function M.lower_equation(field, entry, elab, ndims, reg)
	assert(entry.equation, "lower_equation: entry '" .. field .. "' has no equation")

	local ctx = make_ctx(reg, elab, ndims)
	local out = {}

	if entry.rank == 0 then
		expand_solve_scalar(out, field, entry, ctx)
	elseif entry.rank == 1 then
		expand_solve_vector(out, field, entry, ctx)
	else
		error("lower_equation: rank-" .. tostring(entry.rank) .. " not supported")
	end

	emit_solve_linalg(out, field, entry, ctx)

	local has_div_cells = false
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
