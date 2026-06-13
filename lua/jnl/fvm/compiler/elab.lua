-- jnl/fvm/compiler/elab.lua - Intermediate field elaboration and manifest building
-- <jed@nelson.ac> // 2026-06-13

local Node   = require("jnl.nabla.node")
local Mangle = require("jnl.nabla.mangle")

---@private
local M      = {}

--
-- Internal name manglers for compiler-private intermediates
--

local function mangle_diag(field) return "__diag_" .. field end
local function mangle_facen_sym(field) return "__facen_" .. field end
local function mangle_vec_cache(n, ax) return "__vec_" .. n .. "_" .. ax end
local function mangle_facen_expr(n) return "__facen_expr_" .. n end

-- Exported so lower.lua can reference the same names without duplicating logic.
M.mangle_diag       = mangle_diag
M.mangle_facen_sym  = mangle_facen_sym
M.mangle_vec_cache  = mangle_vec_cache
M.mangle_facen_expr = mangle_facen_expr

--
-- Manifest initialisation
--

local SCRATCH_MIN   = 9

local function init_manifest(reg)
	local man = { cell = {}, face = {}, grad = {}, system = {} }
	reg:each(function(name, entry)
		if entry.kind == "const" or entry.kind == "param" then return end
		man.cell[name] = { ghost = true }
	end)
	return man
end

local function scan_max_scratch(reg, man)
	local max_d = SCRATCH_MIN
	reg:each(function(_, entry)
		if entry.kind == "const" then return end
		local function check(node)
			if not node or not Node.is_node(node) then return end
			local d = node:scratch_depth() + 1
			if d > max_d then max_d = d end
		end
		if entry.expr then check(entry.expr) end
		if entry.correction then check(entry.correction) end
	end)
	man.max_cell_scratch = max_d
end

local function scan_phase_systems(phase, reg, man)
	for _, inst in ipairs(phase) do
		if inst.op ~= "solve" then goto continue end
		local entry = reg:entry(inst.field)
		if not entry then goto continue end
		if entry.rank == 1 then
			local comps = entry.components or { inst.field .. "_x", inst.field .. "_y" }
			for _, c in ipairs(comps) do
				man.system[c] = true
				man.cell[c]   = { ghost = true }
			end
		else
			man.system[inst.field] = true
		end
		::continue::
	end
end

--
-- Elab table helpers
--

local function elab_add_inv(elab, source, iname)
	local t = elab.invalidates[source]
	if not t then
		t = {}; elab.invalidates[source] = t
	end
	for _, v in ipairs(t) do if v == iname then return end end
	t[#t + 1] = iname
end

--
-- Intermediate registration
--

local function elab_add_grad(elab, field, rank)
	local axes = { "x", "y" }
	if rank == 0 then
		for _, ax in ipairs(axes) do
			local gname = Mangle.grad(field, ax)
			if elab.fields[gname] then goto continue end
			elab.fields[gname] = { kind = "grad", source = field, axis = ax, deps = { field } }
			elab_add_inv(elab, field, gname)
			::continue::
		end
	elseif rank == 1 then
		for _, ax in ipairs(axes) do
			local comp = Mangle.field(field, ax)
			for _, gax in ipairs(axes) do
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
	local comps  = (Uentry and Uentry.rank == 1)
		and { Mangle.field(Uname, "x"), Mangle.field(Uname, "y") }
		or { Uname }

	local deps   = {}
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

-- Forward declaration (elab_scan and elab_add_flux_expr are mutually recursive).
local elab_scan

local function elab_add_flux_expr(elab, reg, node, counter)
	local n               = counter[1]; counter[1] = n + 1
	local cx              = mangle_vec_cache(n, "x")
	local cy              = mangle_vec_cache(n, "y")
	local facen           = mangle_facen_expr(n)

	elab.fields[cx]       = { kind = "vec_cache", axis = "x", node = node, deps = {} }
	elab.fields[cy]       = { kind = "vec_cache", axis = "y", node = node, deps = {} }
	elab.face_flux[facen] = { kind = "expr", node = node, vec_x = cx, vec_y = cy, name = facen }

	elab_scan(elab, reg, node, "expr")

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

local function outer_flux_child(a, b)
	if a.kind == "mwi" then return a, b end
	if b.kind == "mwi" then return b, a end
	local a_sym = a.kind == "symbol"
	local b_sym = b.kind == "symbol"
	if a_sym and not b_sym then return b, a end
	if b_sym and not a_sym then return a, b end
	assert(a.rank == 1 and b.rank == 1,
		string.format("outer: cannot identify flux child: (%s) outer (%s)",
			tostring(a), tostring(b)))
	return a, b
end

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
	local n                    = counter[1]; counter[1] = n + 1
	local dname                = "__divcell_" .. n
	local inner                = div_node.a
	local flux_name, flux_kind = elab_flux_for(elab, reg, inner, counter)

	elab.fields[dname]         = {
		kind      = "div_cell",
		flux_name = flux_name,
		flux_kind = flux_kind,
		div_node  = div_node, -- identity key for resolve_div_cells in lower.lua
		deps      = { flux_name },
	}

	local flux_entry           = elab.face_flux[flux_name]
	if flux_entry then
		local sources = flux_entry.deps or flux_entry.comps or {}
		for _, dep in ipairs(sources) do elab_add_inv(elab, dep, dname) end
		if flux_entry.field then elab_add_inv(elab, flux_entry.field, dname) end
	end

	return dname
end

elab_scan = function(elab, reg, node, mode)
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
		elab_scan(elab, reg, node.a, "expr")
		return
	end

	if k == "divergence" then
		if mode == "expr" then
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
		elab_scan(elab, reg, node.a, "expr")
		return
	end

	if k == "outer" then
		if mode == "fvm" then
			local flux, _ = outer_flux_child(node.a, node.b)
			elab_flux_for(elab, reg, flux, elab.counter)
		end
		elab_scan(elab, reg, node.a, "expr")
		elab_scan(elab, reg, node.b, "expr")
		return
	end

	elab_scan(elab, reg, node.a, mode)
	elab_scan(elab, reg, node.b, mode)
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

local function manifest_merge_elab(man, elab)
	for name, entry in pairs(elab.fields) do
		if entry.kind == "grad"
			or entry.kind == "diag"
			or entry.kind == "vec_cache"
			or entry.kind == "div_cell" then
			man.cell[name] = { ghost = true }
		elseif entry.kind == "mwi" then
			man.face[name] = { Uname = entry.U, pname = entry.p }
		end
	end

	for name, entry in pairs(elab.face_flux) do
		if entry.kind == "symbol" then
			man.face[name] = { field = entry.field }
			for _, comp in ipairs(entry.comps or {}) do
				if not man.cell[comp] then man.cell[comp] = { ghost = true } end
			end
		elseif entry.kind == "expr" then
			man.face[name] = { vec_x = entry.vec_x, vec_y = entry.vec_y }
		elseif entry.kind == "mwi" then
			man.face[name] = { Uname = entry.U, pname = entry.p }
		end
	end
end

--
-- Public
--

--- Discover intermediate fields and build the resource manifest.
---
--- Sets alg.elaborated (intermediate registry, face-flux map, invalidation
--- edges) and alg.manifest (cell, face, system, scratch allocations).
--- Must run after expand() so alg.pre/main/post exist for system scanning.
---@param alg Algorithm
---@param reg Registry
function M.elaborate(alg, reg)
	local man = init_manifest(reg)
	scan_phase_systems(alg.pre or {}, reg, man)
	scan_phase_systems(alg.main or {}, reg, man)
	scan_phase_systems(alg.post or {}, reg, man)
	scan_max_scratch(reg, man)

	local elab = build_elab(reg)
	manifest_merge_elab(man, elab)

	alg.manifest   = man
	alg.elaborated = elab
end

return M
