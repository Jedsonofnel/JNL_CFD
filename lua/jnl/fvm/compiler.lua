-- jnl/fvm/compiler.lua expansion compilation pipeline to instructions

local Node = require("jnl.nabla.node")
local Deps = require("jnl.nabla.deps")
local Mangle = require("jnl.nabla.mangle")
local Alg = require("jnl.fvm.algorithm")
local Inst = require("jnl.fvm.instruction")

local M = {}

local AXES = { "x", "y" }

--
-- Name manglers
--

local function mangle_diag(field)
	return "__diag_" .. field
end

local function mangle_facen_sym(field)
	return "__facen_" .. field
end

local function mangle_vec_cache(n, axis)
	return "__vec_" .. n .. "_" .. axis
end

local function mangle_facen_expr(n)
	return "__facen_expr_" .. n
end

--
-- FVM Accessor classification
--

local FVM_ACC_KIND = {
	diag = "matrix",
	prev = "temporal",
	expl = "lagged",
	mwi  = "computed",
}

local function fvm_acc_kind(kind)
	return FVM_ACC_KIND[kind]
end

local function is_auto_fresh(reg, name)
	local e = reg:entry(name)
	if not e or not e.node then return false end
	local k = fvm_acc_kind(e.node.kind)
	return k == "matrix" or k == "temporal" or k == "lagged"
end


--
-- Freshness helpers
--

local function fresh_mark(fresh, inserted, name)
	fresh[name] = true
	inserted[name] = true
end

local function fresh_clear(fresh, inserted, name)
	fresh[name] = nil
	inserted[name] = nil
end

local function invalidate_dependents(reg, field, fresh, inserted)
	local to_clear = {}

	for name in pairs(fresh) do
		if Deps.deps_transitive_invalidation(reg, name, {})[field] then
			to_clear[#to_clear + 1] = name
		end
	end

	for _, name in ipairs(to_clear) do
		fresh_clear(fresh, inserted, name)
	end
end

local function mark_matrix_side_effects(reg, field, fresh, inserted)
	reg:each(function(name, entry)
		if not entry.node then return end
		if fvm_acc_kind(entry.node.kind) ~= "matrix" then return end

		if entry.node.a and entry.node.a.name == field then
			fresh_mark(fresh, inserted, name)
		end
	end)
end

--
-- Compilation: Abstract emission helpers
--

local function build_explicit_set(steps)
	local set = {}

	for _, step in ipairs(steps) do
		if step.op == "solve" or step.op == "correct" or step.op == "zero" then
			set[step.field] = true
		end
	end

	return set
end

local function emit_fills(reg, out)
	local fills = {}

	reg:each(function(name, entry)
		if entry.kind == "const" or entry.kind == "param" then return end
		if entry.solve == false and not entry.is_prescribed then return end
		fills[#fills + 1] = { field = name, value = entry.initial or 0 }
	end)

	table.sort(fills, function(a, b) return a.field < b.field end)

	for _, f in ipairs(fills) do
		out[#out + 1] = Inst.fill(f.field, f.value)
	end
end

local function emit_pre_evaluates(reg, pre_names, inserted, fresh, out)
	for _, name in ipairs(Deps.topo_sort(reg, pre_names)) do
		local entry = reg:entry(name)
		if entry.is_prescribed or entry.kind == "const" or not entry.expr then
			goto continue
		end

		out[#out + 1] = Inst.evaluate(name)
		fresh_mark(fresh, inserted, name)

		::continue::
	end
end

local function emit_post_evaluates(reg, post_names, inserted)
	local out = {}

	for _, name in ipairs(Deps.topo_sort(reg, post_names)) do
		if inserted[name] then goto continue end

		local entry = reg:entry(name)
		if not entry then goto continue end

		if entry.solve == true then
			out[#out + 1] = Inst.solve(name)
		elseif entry.expr then
			out[#out + 1] = Inst.evaluate(name)
		end

		::continue::
	end

	return out
end

-- emit an implicit solve abstract step with all side-effects
local function emit_implicit_solve(reg, name, fresh, inserted, out)
	local entry = reg:entry(name)
	out[#out + 1] = Inst.solve(name)

	invalidate_dependents(reg, name, fresh, inserted)
	fresh_mark(fresh, inserted, name)
	mark_matrix_side_effects(reg, name, fresh, inserted)

	if entry.correction then
		out[#out + 1] = Inst.correct(name)
	end
	if entry.clip then
		out[#out + 1] = Inst.clip(name, entry.clip[1], entry.clip[2])
	end
end

-- forward declarations for mutual recursion
local emit_deps_for
local expand_steps
local expand_inner

emit_deps_for = function(reg, field, sorted_main, inserted, fresh, out)
	local tdeps = Deps.deps_transitive(reg, field, {})

	for _, name in ipairs(sorted_main) do
		if not tdeps[name] or inserted[name] then goto continue end

		if is_auto_fresh(reg, name) then
			fresh_mark(fresh, inserted, name)
			goto continue
		end

		local entry = reg:entry(name)
		if entry.solve == true then
			emit_implicit_solve(reg, name, fresh, inserted, out)
		else
			out[#out + 1] = Inst.evaluate(name)
			fresh_mark(fresh, inserted, name)
		end

		::continue::
	end
end

--
-- Compilation: abstract expand dispatch
--

local abstract_dispatch = {}

abstract_dispatch.solve = function(step, ctx, out)
	emit_deps_for(ctx.reg, step.field, ctx.sorted_main, ctx.inserted, ctx.fresh, out)

	if ctx.inserted[step.field] then return end

	local inst = Inst.solve(step.field)
	inst.fields.tag = step.tag
	out[#out + 1] = inst

	invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
	fresh_mark(ctx.fresh, ctx.inserted, step.field)
	mark_matrix_side_effects(ctx.reg, step.field, ctx.fresh, ctx.inserted)

	local entry = ctx.reg:entry(step.field)
	if entry and entry.clip then
		out[#out + 1] = Inst.clip(step.field, entry.clip[1], entry.clip[2])
	end
end

abstract_dispatch.correct = function(step, _, out)
	out[#out + 1] = Inst.correct(step.field)
end

abstract_dispatch.zero = function(step, ctx, out)
	out[#out + 1] = Inst.zero(step.field)

	fresh_clear(ctx.fresh, ctx.inserted, step.field)
	invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
end

abstract_dispatch.evaluate = function(step, ctx, out)
	local entry = ctx.reg:entry(step.field)
	if not entry or not entry.expr then return end

	emit_deps_for(ctx.reg, step.field, ctx.sorted_main, ctx.inserted, ctx.fresh, out)

	if ctx.fresh[step.field] then return end

	local inst = Inst.evaluate(step.field, not step.user)
	out[#out + 1] = inst

	fresh_mark(ctx.fresh, ctx.inserted, step.field)
end

abstract_dispatch.inner = function(step, ctx, out)
	local inner = expand_inner(step.alg, ctx.reg, ctx.inserted, ctx.fresh, ctx.explicit_set)
	out[#out + 1] = Inst.new("inner", { alg = inner, level = "abstract" })
end

expand_steps = function(reg, steps, sorted_main, inserted, fresh, explicit_set)
	local ctx = {
		reg          = reg,
		sorted_main  = sorted_main,
		inserted     = inserted,
		fresh        = fresh,
		explicit_set = explicit_set,
	}

	local out = {}
	for _, step in ipairs(steps) do
		local fn = abstract_dispatch[step.op]
		if fn then
			fn(step, ctx, out)
		else
			out[#out + 1] = Inst.new(step.op, { field = step.field })
		end
	end
	return out
end

expand_inner = function(alg, reg, inserted, fresh, outer_explicit)
	local explicit = build_explicit_set(alg.steps)
	for k in pairs(outer_explicit) do
		explicit[k] = true
	end

	local _, main_names, _ = Deps.classify(reg, explicit)
	local sorted_main = Deps.topo_sort(reg, main_names)

	local result = Alg.new(alg.label)
	result.op = alg.op
	result.max_iters = alg.max_iters
	result.main = expand_steps(reg, alg.steps, sorted_main, inserted, fresh, explicit)
	return result
end

--
-- Compilation: manifest
--

local JNL_FVM_REAL_CELL_SCRATCH_MIN = 9

local function init_manifest(reg)
	local man = { cell = {}, face = {}, grad = {}, system = {} }

	reg:each(function(name, entry)
		if entry.kind == "const" or entry.kind == "param" then return end
		man.cell[name] = { ghost = true }
	end)

	return man
end

local function scan_max_scratch(reg, man)
	local max_d = JNL_FVM_REAL_CELL_SCRATCH_MIN

	reg:each(function(_, entry)
		if entry.kind == "const" then return end

		local function check(node)
			if not node or not Node.is_node(node) then return end
			-- +1: jnl_expr_eval leaves one result live after returning
			local d = node:scratch_depth() + 1
			if d > max_d then max_d = d end
		end

		-- equation lhs/rhs become assembly calls, not jnl_expr_eval — skip them
		if entry.expr then check(entry.expr) end
		if entry.correction then check(entry.correction) end
	end)

	man.max_cell_scratch = max_d
end

local function scan_node_resources(node, man)
	if not node or type(node) ~= "table" then return end

	if node.kind == "laplacian" then
		local field = node.b and node.b.name
		if field then
			man.grad[Mangle.grad(field, "x")] = true
			man.grad[Mangle.grad(field, "y")] = true
		end
	elseif node.kind == "mwi" or node.kind == "div_mwi" then
		if node.a and node.b and node.a.name and node.b.name then
			local mwi_name = Mangle.accessor("mwi", node)
			man.face[mwi_name] = { Uname = node.a.name, pname = node.b.name }
		end
	end

	scan_node_resources(node.a, man)
	scan_node_resources(node.b, man)
end

local function scan_reg_resources(reg, man)
	reg:each(function(_, entry)
		if entry.equation then
			scan_node_resources(entry.equation.lhs, man)
			scan_node_resources(entry.equation.rhs, man)
		end

		if entry.expr then
			scan_node_resources(entry.expr, man)
		end
		if entry.correction then
			scan_node_resources(entry.correction, man)
		end
	end)
end

local function scan_phase_systems(phase, reg, man)
	for _, inst in ipairs(phase) do
		if inst.op ~= "solve" then goto continue end

		local field = inst.field
		local entry = reg:entry(field)
		if not entry then goto continue end

		if entry.rank == 1 then
			local comps = entry.components or { field .. "_x", field .. "_y" }
			for _, c in ipairs(comps) do
				man.system[c] = true
				man.cell[c]   = { ghost = true }
			end
		else
			man.system[field] = true
		end

		::continue::
	end
end

--
-- Elaboration: elaborating intermediates
--

-- NOTE: intermediate -> { kind, source fields, ... }
-- NOTE: invalidates  -> registry field name -> list of intermediate names

-- forward declaration
local elab_scan

local function elab_add_inv(elab, source, iname)
	local t = elab.invalidates[source]
	if not t then
		t = {}; elab.invalidates[source] = t
	end
	for _, v in ipairs(t) do if v == iname then return end end
	t[#t + 1] = iname
end

local function elab_add_grad(elab, field, rank)
	if rank == 0 then
		for _, ax in ipairs({ "x", "y" }) do
			local gname = Mangle.grad(field, ax)
			if elab.fields[gname] then goto continue end

			elab.fields[gname] = { kind = "grad", source = field, axis = ax, deps = { field } }
			elab_add_inv(elab, field, gname)

			::continue::
		end
	elseif rank == 1 then
		for _, ax in ipairs({ "x", "y" }) do
			local comp = Mangle.field(field, ax)

			for _, gax in ipairs({ "x", "y" }) do
				local gname = Mangle.grad(comp, gax)
				if elab.fields[gname] then goto continue end

				elab.fields[gname] = { kind = "grad", source = comp, axis = gax, deps = { comp } }
				elab_add_inv(elab, comp, gname)
				elab_add_inv(elab, field, gname)

				::continue::
			end
		end
	end
end

local function elab_add_mwi(elab, reg, mwi_node)
	local Uname = mwi_node.a.name
	local pname = mwi_node.b.name
	local mname = Mangle.accessor("mwi", mwi_node)

	if elab.fields[mname] then return end

	local Uentry = reg:entry(Uname)
	local comps  = {}

	if Uentry and Uentry.rank == 1 then
		comps = { Mangle.field(Uname, "x"), Mangle.field(Uname, "y") }
	else
		comps = { Uname }
	end

	local deps = {}

	for _, comp in ipairs(comps) do
		local dname = mangle_diag(comp)

		if not elab.fields[dname] then
			elab.fields[dname] = { kind = "diag", source = comp, deps = { comp } }
			elab_add_inv(elab, comp, dname)
			elab_add_inv(elab, Uname, dname)
		end

		deps[#deps + 1] = comp
		deps[#deps + 1] = dname
	end

	deps[#deps + 1] = pname

	elab.fields[mname] = { kind = "mwi", U = Uname, p = pname, deps = deps }

	for _, comp in ipairs(comps) do elab_add_inv(elab, comp, mname) end
	elab_add_inv(elab, Uname, mname)
	elab_add_inv(elab, pname, mname)
end

local function elab_add_flux_expr(elab, reg, node, counter)
	local n = counter[1]
	counter[1] = n + 1

	local cx = mangle_vec_cache(n, "x")
	local cy = mangle_vec_cache(n, "y")
	local facen = mangle_facen_expr(n)

	elab.fields[cx] = { kind = "vec_cache", axis = "x", node = node, deps = {} }
	elab.fields[cy] = { kind = "vec_cache", axis = "y", node = node, deps = {} }
	elab.face_flux[facen] = { kind = "expr", node = node, vec_x = cx, vec_y = cy, name = facen }

	-- scan sub-expression in expr mode so any nested intermediates
	-- (grads, div_cells, etc.) get registered with their own entries
	elab_scan(elab, reg, node, "expr")

	-- wire invalidation edges specifically for cx, cy, facen
	-- must run after elab_scan so nested intermediate entries exist
	local function collect_inv(n2)
		if not n2 or not Node.is_node(n2) then return end
		if n2.kind == "symbol" and n2.name then
			local name = n2.name
			elab_add_inv(elab, name, facen)
			elab_add_inv(elab, name, cx)
			elab_add_inv(elab, name, cy)
			if n2.rank == 1 then
				for _, ax in ipairs({ "x", "y" }) do
					local comp = Mangle.field(name, ax)
					elab_add_inv(elab, comp, facen)
					elab_add_inv(elab, comp, cx)
					elab_add_inv(elab, comp, cy)
				end
			end
		end

		-- also invalidate from any nested intermediates this expression depends on
		if n2.kind == "grad" and n2.a and n2.a.name then
			for _, ax in ipairs({ "x", "y" }) do
				local gname = Mangle.grad(n2.a.name, ax)
				elab_add_inv(elab, gname, facen)
				elab_add_inv(elab, gname, cx)
				elab_add_inv(elab, gname, cy)
			end
		end
		collect_inv(n2.a)
		collect_inv(n2.b)
	end

	collect_inv(node)

	return facen
end

local function elab_add_flux_symbol(elab, reg, field_name)
	local facen_name = mangle_facen_sym(field_name)
	if elab.face_flux[facen_name] then return facen_name end

	local entry = reg:entry(field_name)
	if not (entry and entry.rank == 1) then
		error("elab_add_flux_symbol: '" .. field_name .. "' is not rank-1")
	end

	local comps = { Mangle.field(field_name, "x"), Mangle.field(field_name, "y") }

	elab.face_flux[facen_name] = {
		kind  = "symbol",
		field = field_name,
		comps = comps,
		name  = facen_name,
	}

	for _, comp in ipairs(comps) do
		elab_add_inv(elab, comp, facen_name)
		elab_add_inv(elab, field_name, facen_name)
	end

	return facen_name
end

local function elab_flux_for(elab, reg, flux_node, counter)
	if flux_node.kind == "mwi" then
		elab_add_mwi(elab, reg, flux_node)
		return Mangle.accessor("mwi", flux_node), "mwi"
	elseif flux_node.kind == "symbol" then
		return elab_add_flux_symbol(elab, reg, flux_node.name), "symbol"
	else
		return elab_add_flux_expr(elab, reg, flux_node, counter), "expr"
	end
end

-- find which child of outer() is the convecting flux
-- mwi wins unconditionally; otherwise the non-symbol or first rank-1 child
local function outer_flux_child(a, b)
	if a.kind == "mwi" then return a, b end
	if b.kind == "mwi" then return b, a end

	-- neither is mwi: prefer the non-symbol side as the "interesting" flux
	local a_sym = a.kind == "symbol"
	local b_sym = b.kind == "symbol"

	if a_sym and not b_sym then return b, a end
	if b_sym and not a_sym then return a, b end

	-- both symbols or both exprs: assert rank-1 on both and take a by convention,
	-- but warn — this case is genuinely ambiguous
	assert(a.rank == 1 and b.rank == 1,
		string.format("outer: cannot identify flux child: (%s) outer (%s)", tostring(a), tostring(b)))

	return a, b
end

-- walk a scale chain to find the rank >= 1 symbol leaf (the field being diffused)
local function field_in_scale(node)
	if not node then return nil end
	if node.kind == "symbol" then return node end
	if node.kind == "scale" then return field_in_scale(node.b) end
	if node.kind == "mul" then
		local b = field_in_scale(node.b)
		if b then return b end
		return field_in_scale(node.a)
	end
	return nil
end

local function elab_add_div_cell(elab, reg, div_node, counter)
	local n = counter[1]
	counter[1] = n + 1
	local dname = "__divcell_" .. n

	-- the divergence still needs a face flux; register that too
	local inner = div_node.a
	local flux_name, flux_kind = elab_flux_for(elab, reg, inner, counter)

	elab.fields[dname] = {
		kind = "div_cell",
		flux_name = flux_name,
		flux_kind = flux_kind,
		deps = { flux_name },
	}

	-- propagate invalidation from the flux entry's own deps
	local flux_entry = elab.face_flux[flux_name]
	if flux_entry then
		-- symbol entries use comps/field; expr/mwi entries use deps
		local sources = flux_entry.deps or flux_entry.comps or {}
		for _, dep in ipairs(sources) do
			elab_add_inv(elab, dep, dname)
		end
		if flux_entry.field then
			elab_add_inv(elab, flux_entry.field, dname)
		end
	end

	return dname
end

elab_scan = function(elab, reg, node, mode)
	-- mode: "fvm"  = top-level equation, implicit operators are assembly
	--       "expr" = inside coefficient/correction/defined_as, operators are explicit
	mode = mode or "fvm"
	if not node or type(node) ~= "table" then return end
	if not Node.is_node(node) then return end

	local k = node.kind

	if k == "mwi" then
		elab_add_mwi(elab, reg, node)
		return
	end

	if k == "grad" then
		local op = node.a
		if op and op.kind == "symbol" and op.name then
			local e = reg:entry(op.name)
			elab_add_grad(elab, op.name, e and e.rank or op.rank or 0)
		end
		elab_scan(elab, reg, node.a, mode)
		return
	end

	if k == "laplacian" then
		local fnode = field_in_scale(node.a)
		if fnode and fnode.name then
			local e = reg:entry(fnode.name)
			elab_add_grad(elab, fnode.name, e and e.rank or fnode.rank or 0)
		end
		-- coefficient sub-expressions are always explicit, never FVM assembly
		elab_scan(elab, reg, node.a, "expr")
		return
	end

	if k == "divergence" then
		if mode == "expr" then
			-- div in coefficient position: needs explicit scalar evaluation
			elab_add_div_cell(elab, reg, node, elab.counter)
		else
			local inner = node.a
			if inner.kind == "outer" then
				local flux, _ = outer_flux_child(inner.a, inner.b)
				elab_flux_for(elab, reg, flux, elab.counter)
			else
				elab_flux_for(elab, reg, inner, elab.counter)
			end
		end
		-- always recurse in expr mode: sub-nodes of a div are never top-level FVM terms
		elab_scan(elab, reg, node.a, "expr")
		return
	end

	if k == "outer" then
		if mode == "fvm" then
			local flux, _ = outer_flux_child(node.a, node.b)
			elab_flux_for(elab, reg, flux, elab.counter)
		end
		-- children of outer are expressions, not top-level FVM terms
		elab_scan(elab, reg, node.a, "expr")
		elab_scan(elab, reg, node.b, "expr")
		return
	end

	elab_scan(elab, reg, node.a, mode)
	elab_scan(elab, reg, node.b, mode)
end

local function manifest_merge_elab(man, elab)
	for name, entry in pairs(elab.fields) do
		if entry.kind == "grad" or entry.kind == "diag"
			or entry.kind == "vec_cache" or entry.kind == "div_cell" then
			man.cell[name] = { ghost = true }
		end
	end
	for name, entry in pairs(elab.face_flux) do
		if entry.kind == "symbol" then
			man.face[name] = { field = entry.field }
		elseif entry.kind == "expr" then
			man.face[name] = { vec_x = entry.vec_x, vec_y = entry.vec_y }
		end
		-- mwi already in man.face from scan_node_resources
	end
end

local function build_elab(reg)
	local elab = { fields = {}, invalidates = {}, face_flux = {}, counter = { 1 } }

	reg:each(function(_, entry)
		if entry.kind == "const" then return end

		if entry.equation then
			elab_scan(elab, reg, entry.equation.lhs, "fvm")
			elab_scan(elab, reg, entry.equation.rhs, "fvm")
		end
		if entry.expr then elab_scan(elab, reg, entry.expr, "expr") end
		if entry.correction then elab_scan(elab, reg, entry.correction, "expr") end
	end)

	return elab
end
-- Node helpers
local function neg_node(n)
	if n.kind == "constant" then return Node.const(-n.a) end
	if n.kind == "neg" then return n.a end
	return n:neg()
end

local function sign_node(n, s)
	return s == 1 and n or neg_node(n)
end

-- Classify a coefficient node into one of three dispatch cases.
-- Always returns a Node as the second value so callers are uniformly typed:
--   "k",    const_node   -- use _k variant; number is cn.a
--   "f",    symbol_node  -- use _f variant; field name is cn.name
--   "expr", expr_node    -- emit eval_coeff(cn) then use "__coeff" string
local function classify_coeff(node, sign)
	if node == nil then
		return "k", Node.const(sign == 1 and 1.0 or -1.0)
	end
	local n = sign_node(node, sign)
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
-- BC ghost fills
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

local function emit_ddt_comp(out, comp, rho_node, sign)
	local ck, cn = classify_coeff(rho_node, sign)
	setup_coeff(out, ck, cn)
	if ck == "k" then
		out[#out + 1] = Inst.ddt_k(comp, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.ddt_f(comp, cn.name, cn)
	else
		out[#out + 1] = Inst.ddt_f(comp, "__coeff", cn)
	end
end

local function emit_lap_comp(out, comp, coeff_node, sign)
	local ck, cn = classify_coeff(coeff_node, sign)
	local gx     = Mangle.grad(comp, "x")
	local gy     = Mangle.grad(comp, "y")

	setup_coeff(out, ck, cn)
	if ck == "k" then
		out[#out + 1] = Inst.lap_k(comp, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.lap_f(comp, cn.name, cn)
	else
		out[#out + 1] = Inst.lap_f(comp, "__coeff", cn)
	end

	-- always emit non-ortho correction; runner no-ops if non_ortho=false for this field
	if ck == "expr" then out[#out + 1] = Inst.eval_coeff(cn) end
	if ck == "k" then
		out[#out + 1] = Inst.lap_nonorth_k(comp, gx, gy, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.lap_nonorth_f(comp, gx, gy, cn.name, cn)
	else
		out[#out + 1] = Inst.lap_nonorth_f(comp, gx, gy, "__coeff", cn)
	end
end

local function emit_div_comp(out, comp, flux_name, rho_node, sign)
	local ck, cn = classify_coeff(rho_node, sign)
	setup_coeff(out, ck, cn)
	if ck == "k" then
		out[#out + 1] = Inst.div_k(comp, flux_name, cn:to_number())
	elseif ck == "f" then
		out[#out + 1] = Inst.div_f(comp, flux_name, cn.name, cn)
	else
		out[#out + 1] = Inst.div_f(comp, flux_name, "__coeff", cn)
	end

	-- always emit TVD deferred correction; runner no-ops for uds/cds scheme config
	out[#out + 1] = Inst.div_dc(comp, flux_name,
		Mangle.grad(comp, "x"), Mangle.grad(comp, "y"))
end

--
-- Explicit source emitters
-- Sign rule: term at walk sign s contributes b += (-s * value).
--

local function emit_su_field_comp(out, comp, src_name, sign, display_node)
	out[#out + 1] = Inst.su_fs(comp, -sign, src_name, true, display_node)
end

local function emit_su_const_comp(out, comp, value, sign)
	if value == 0 then return end
	out[#out + 1] = Inst.su_k(comp, -sign * value, true)
end

-- div(mwi) as explicit source: evaluate divergence into __coeff then accumulate.
-- integrated=false: face-divergence is an area-weighted sum, not volumetric.
-- Runner su_fs dispatch must use _coeff() when src="__coeff".
local function emit_su_div_coeff(out, comp, div_node, sign)
	out[#out + 1] = Inst.eval_coeff(div_node)
	out[#out + 1] = Inst.su_fs(comp, -sign, "__coeff", false, div_node)
end

--
-- Forward declarations
--

local walk_scalar_node
local walk_vector_node
local lower_alg

--
-- Scalar walk dispatch
-- Handlers: fn(out, node, field, sign, elab)
--

local walk_scalar      = {}

walk_scalar.add        = function(out, node, field, sign, elab)
	walk_scalar_node(out, node.a, field, sign, elab)
	walk_scalar_node(out, node.b, field, sign, elab)
end

walk_scalar.sub        = function(out, node, field, sign, elab)
	walk_scalar_node(out, node.a, field, sign, elab)
	walk_scalar_node(out, node.b, field, -sign, elab)
end

walk_scalar.neg        = function(out, node, field, sign, elab)
	walk_scalar_node(out, node.a, field, -sign, elab)
end

walk_scalar.ddt        = function(out, node, field, sign, _)
	local rho, phi = extract_scale(node.a, "ddt")
	if phi.name ~= field then return end
	emit_ddt_comp(out, field, rho, sign)
end

walk_scalar.laplacian  = function(out, node, field, sign, _)
	local coeff, phi = extract_scale(node.a, "laplacian")
	if phi.name ~= field then return end
	emit_lap_comp(out, field, coeff, sign)
end

walk_scalar.divergence = function(out, node, field, sign, _)
	local inner = node.a

	if inner.kind == "scale" and inner.b.kind == "mwi" and inner.a.name == field then
		emit_div_comp(out, field, Mangle.accessor("mwi", inner.b), nil, sign)
		return
	end

	if inner.kind == "mwi" then
		emit_su_div_coeff(out, field, node, sign)
		return
	end
end

walk_scalar.symbol     = function(out, node, field, sign, _)
	if node.name == field then return end
	emit_su_field_comp(out, field, node.name, sign, node)
end

walk_scalar.constant   = function(out, node, field, sign, _)
	emit_su_const_comp(out, field, node.a, sign)
end

walk_scalar.mwi        = function() end
walk_scalar.accessor   = function() end
walk_scalar.grad       = function() end

--
-- Vector walk dispatch
-- Handlers: fn(out, node, field, comps, sign, elab)
--

local walk_vector      = {}

walk_vector.add        = function(out, node, field, comps, sign, elab)
	walk_vector_node(out, node.a, field, comps, sign, elab)
	walk_vector_node(out, node.b, field, comps, sign, elab)
end

walk_vector.sub        = function(out, node, field, comps, sign, elab)
	walk_vector_node(out, node.a, field, comps, sign, elab)
	walk_vector_node(out, node.b, field, comps, -sign, elab)
end

walk_vector.neg        = function(out, node, field, comps, sign, elab)
	walk_vector_node(out, node.a, field, comps, -sign, elab)
end

walk_vector.ddt        = function(out, node, _, comps, sign, _)
	local rho, _ = extract_scale(node.a, "ddt")
	for _, comp in ipairs(comps) do
		emit_ddt_comp(out, comp, rho, sign)
	end
end

walk_vector.laplacian  = function(out, node, _, comps, sign, _)
	local coeff, _ = extract_scale(node.a, "laplacian")
	for _, comp in ipairs(comps) do
		emit_lap_comp(out, comp, coeff, sign)
	end
end

walk_vector.divergence = function(out, node, _, comps, sign, _)
	local inner = node.a

	if inner.kind == "outer" then
		local flux_node = inner.a.kind == "mwi" and inner.a or inner.b
		local flux      = Mangle.accessor("mwi", flux_node)
		for _, comp in ipairs(comps) do
			emit_div_comp(out, comp, flux, nil, sign)
		end
		return
	end
end

walk_vector.grad       = function(out, node, _, comps, sign, _)
	local scalar = node.a
	assert(scalar.rank == 0 and scalar.name,
		"lower: grad source in vector equation has no named scalar")
	for i, comp in ipairs(comps) do
		emit_su_field_comp(out, comp, Mangle.grad(scalar.name, AXES[i]), sign, node)
	end
end

walk_vector.cvec       = function(out, node, _, comps, sign, _)
	for i, comp in ipairs(comps) do
		emit_su_const_comp(out, comp, node.a and node.a[i] or 0, sign)
	end
end

walk_vector.constant   = function(out, node, _, comps, sign, _)
	for _, comp in ipairs(comps) do
		emit_su_const_comp(out, comp, node.a, sign)
	end
end

--
-- Walker implementations (resolves forward declarations)
--

walk_scalar_node       = function(out, node, field, sign, elab)
	if not node then return end
	local fn = walk_scalar[node.kind]
	if fn then
		fn(out, node, field, sign, elab)
	else
		out[#out + 1] = Inst.new("comment",
			{ text = "lower: unhandled scalar node '" .. tostring(node.kind) .. "'" })
	end
end

walk_vector_node       = function(out, node, field, comps, sign, elab)
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
	out[#out + 1] = Inst.sys_reset(field)

	walk_scalar_node(out, entry.equation.lhs, field, 1, elab)
	walk_scalar_node(out, entry.equation.rhs, field, -1, elab)

	emit_bc_close_scalar(out, field, entry.bcs)

	if elab.fields["__diag_" .. field] then
		out[#out + 1] = Inst.diag_snapshot(field, "__diag_" .. field)
	end
end

local function expand_solve_vector(out, field, entry, elab)
	local comps  = vec_comps(field, entry)
	local ux, uy = comps[1], comps[2]

	emit_ghost_fills_vector(out, ux, uy, entry.bcs)

	for _, comp in ipairs(comps) do
		out[#out + 1] = Inst.sys_reset(comp)
	end

	walk_vector_node(out, entry.equation.lhs, field, comps, 1, elab)
	walk_vector_node(out, entry.equation.rhs, field, comps, -1, elab)

	-- vector bc close (pclose_v_*) not yet in instruction set; TODO when added

	for _, comp in ipairs(comps) do
		if elab.fields["__diag_" .. comp] then
			out[#out + 1] = Inst.diag_snapshot(comp, "__diag_" .. comp)
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

local function expand_solve(field, entry, elab)
	local out = {}

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

--
-- Other abstract instruction expansions
--

local function expand_evaluate(field, entry)
	if not entry or not entry.expr then return {} end
	return { Inst.eval_expr(field, entry.expr) }
end

local function expand_correct(field, entry)
	if not entry or not entry.correction then return {} end
	return { Inst.apply_correction(field, entry.correction) }
end

--
-- Abstract -> concrete dispatch
--

local abstract_expand = {}

abstract_expand.solve = function(inst, reg, elab)
	return expand_solve(inst.field, reg:entry(inst.field), elab)
end

abstract_expand.evaluate = function(inst, reg, _)
	return expand_evaluate(inst.field, reg:entry(inst.field))
end

abstract_expand.correct = function(inst, reg, _)
	return expand_correct(inst.field, reg:entry(inst.field))
end

abstract_expand.inner = function(inst, reg, elab)
	local inner = inst.fields and inst.fields.alg
	if inner then lower_alg(inner, reg, elab) end
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

lower_alg = function(alg, reg, elab)
	alg.pre  = lower_phase(alg.pre or {}, reg, elab)
	alg.main = lower_phase(alg.main or {}, reg, elab)
	alg.post = lower_phase(alg.post or {}, reg, elab)
end










--
-- Consolidating
--

local function expand(alg, reg)
	local inserted                          = {}
	local fresh                             = {}
	local explicit                          = build_explicit_set(alg.steps)
	local pre_names, main_names, post_names = Deps.classify(reg, explicit)
	local sorted_main                       = Deps.topo_sort(reg, main_names)

	local pre                               = {}
	emit_fills(reg, pre)
	emit_pre_evaluates(reg, pre_names, inserted, fresh, pre)

	alg.pre  = pre
	alg.main = expand_steps(reg, alg.steps, sorted_main, inserted, fresh, explicit)
	alg.post = emit_post_evaluates(reg, post_names, inserted)
end

local function manifest(alg, reg)
	local man = init_manifest(reg)
	scan_reg_resources(reg, man)
	scan_phase_systems(alg.pre, reg, man)
	scan_phase_systems(alg.main, reg, man)
	scan_phase_systems(alg.post, reg, man)
	scan_max_scratch(reg, man)
	alg.manifest = man
end

local function elaborate(alg, reg)
	alg.elaborated = build_elab(reg)
	manifest_merge_elab(alg.manifest, alg.elaborated)
end

local function lower(alg, reg)
	local elab = alg.elaborated
	assert(elab, "compiler: alg.elaborated is nil")
	lower_alg(alg, reg, elab)
end

--
-- Public entry point
--

M.expand = expand
M.manifest = manifest
M.elaborate = elaborate

function M.compile(alg, reg)
	expand(alg, reg)
	manifest(alg, reg)
	elaborate(alg, reg)
	lower(alg, reg)
end

return M
