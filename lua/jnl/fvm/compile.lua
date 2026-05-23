-- fvm/compile.lua - resource counting and instruction emission
-- <jed@nelson.ac> // 2026-05-22

local E      = require("jnl.core.expr")
local FVMe   = require("jnl.fvm.expr")
local names  = FVMe.names

local M      = {}

--
-- Instruction object
--

local Inst   = {}
Inst.__index = Inst

function Inst.new(op, fields)
	return setmetatable({ op = op, fields = fields or {} }, Inst)
end

function Inst.comment(message)
	return Inst.new("comment", { message = message })
end

function Inst:__index(k)
	-- transparent field access: inst.field, inst.solver etc
	if Inst[k] then return Inst[k] end
	return self.fields[k]
end

local fmt = function(n) return require("jnl.core.expr").pretty_sym(n) end

local printers = {
	comment = function(f)
		return "\n  ; " .. f.message
	end,
	face_interp_cds = function(f)
		return string.format("FACE_INTERP   %s  ->  %s", fmt(f.field), fmt(f.out))
	end,
	grad_green_gauss = function(f)
		return string.format("GRAD_GG       %s  ->  (%s, %s)",
			fmt(f.face_field), fmt(f.out_x), fmt(f.out_y))
	end,
	rhie_chow = function(f)
		return string.format("RHIE_CHOW     (%s,%s) p=%s  ->  %s",
			fmt(f.Ux), fmt(f.Uy), fmt(f.p), fmt(f.out))
	end,
	divergence = function(f)
		return string.format("DIVERGENCE    %s  ->  %s", fmt(f.un_face), fmt(f.out))
	end,
	eval_expr = function(f)
		return string.format("EVAL_EXPR     %s  =  %s", fmt(f.name), tostring(f.expr))
	end,
	eval_coeff = function(f)
		return string.format("| EVAL_COEFF  %s", tostring(f.expr))
	end,
	assemble = function(f)
		local relax = f.relax and string.format(" [relax=%g]", f.relax) or ""
		return string.format("ASSEMBLE      %s%s", fmt(f.field), relax)
	end,
	solve = function(f)
		return string.format("SOLVE         %s  [%s tol=%g iters=%d]",
			fmt(f.field), f.solver, f.tol, f.max_iters)
	end,
	apply_bc_patch = function(f)
		local val = f.value ~= nil and string.format("  %g", f.value) or ""
		return string.format("APPLY_BC      %-16s patch=%-10s %s%s",
			fmt(f.field), f.patch, f.kind, val)
	end,
	apply_bc_face = function(f)
		local val = f.value ~= nil and string.format("  %g", f.value) or ""
		return string.format("APPLY_BC_FACE %-16s patch=%-10s %s%s",
			fmt(f.face_field), f.patch, f.kind, val)
	end,
	bc_placeholder = function(f)
		local field_str = fmt(f.field)
		if f.patch then
			local tag = f.implicit
				and "neumann_const  0.0  [implicit default]"
				or "[no bc registered]"
			return string.format("; BC          %-16s patch=%-10s %s",
				field_str, f.patch, tag)
		else
			return string.format("; BC          %-16s [no mesh — bc unknown]", field_str)
		end
	end,
	sys_reset = function(f)
		return string.format("SYS_RESET     %s", fmt(f.field))
	end,
	ddt_const = function(f)
		return string.format("DDT_CONST     %s  rho=%g  phi0=%s",
			fmt(f.field), f.coeff, fmt(f.phi_prev))
	end,
	ddt_field = function(f)
		local coeff = f.coeff == "__coeff" and "<coeff>" or fmt(f.coeff)
		return string.format("DDT_FIELD     %s  rho=%s  phi0=%s",
			fmt(f.field), coeff, fmt(f.phi_prev))
	end,
	laplacian_const = function(f)
		return string.format("LAP_CONST     %s  gamma=%g", fmt(f.field), f.gamma)
	end,
	laplacian_field = function(f)
		local g = f.gamma == "__coeff" and "<coeff>" or fmt(f.gamma)
		return string.format("LAP_FIELD     %s  gamma=%s", fmt(f.field), g)
	end,
	laplacian_field_harmonic = function(f)
		local g = f.gamma == "__coeff" and "<coeff>" or fmt(f.gamma)
		return string.format("LAP_HARMONIC  %s  gamma=%s", fmt(f.field), g)
	end,
	laplacian_nonorth_field = function(f)
		local g = f.gamma == "__coeff" and "<coeff>" or fmt(f.gamma)
		return string.format("LAP_NONORTH   %s  gamma=%s  grad=(%s,%s)",
			fmt(f.field), g, fmt(f.grad_x), fmt(f.grad_y))
	end,
	laplacian_nonorth_const = function(f)
		return string.format("LAP_NONORTH   %s  gamma=%g  grad=(%s,%s)",
			fmt(f.field), f.gamma, fmt(f.grad_x), fmt(f.grad_y))
	end,
	div_uds_const = function(f)
		return string.format("DIV_UDS_CONST %s  rho=%g  flux=%s",
			fmt(f.field), f.coeff, fmt(f.un_face))
	end,
	div_uds_field = function(f)
		local coeff = f.coeff == "__coeff" and "<coeff>" or fmt(f.coeff)
		return string.format("DIV_UDS_FIELD %s  rho=%s  flux=%s",
			fmt(f.field), coeff, fmt(f.un_face))
	end,
	div_cds_field = function(f)
		local coeff = f.coeff == "__coeff" and "<coeff>" or fmt(f.coeff)
		return string.format("DIV_CDS_FIELD %s  rho=%s  flux=%s",
			fmt(f.field), coeff, fmt(f.un_face))
	end,
	div_cds_const = function(f)
		return string.format("DIV_CDS_CONST %s  rho=%g  flux=%s",
			fmt(f.field), f.coeff, fmt(f.un_face))
	end,
	div_tvd_minmod = function(f)
		return string.format("DIV_TVD_MM    %s  flux=%s", fmt(f.field), fmt(f.un_face))
	end,
	div_tvd_van_leer = function(f)
		return string.format("DIV_TVD_VL    %s  flux=%s", fmt(f.field), fmt(f.un_face))
	end,
	div_tvd_superbee = function(f)
		return string.format("DIV_TVD_SB    %s  flux=%s", fmt(f.field), fmt(f.un_face))
	end,
	su_integrated = function(f)
		local src = f.expr and tostring(f.expr) or fmt(f.src)
		return string.format("SU            %s  src=%s", fmt(f.field), src)
	end,
	sp_integrated = function(f)
		local src = f.expr and tostring(f.expr) or fmt(f.src)
		return string.format("SP            %s  src=%s", fmt(f.field), src)
	end,
	under_relax = function(f)
		return string.format("UNDER_RELAX   %s  alpha=%g", fmt(f.field), f.alpha)
	end,
	apply_correction = function(f)
		return string.format("CORRECT       %s  =  %s", fmt(f.field), tostring(f.expr))
	end,
	clip = function(f)
		local hi = f.hi == math.huge and "inf" or string.format("%g", f.hi)
		return string.format("CLIP          %s  [%g, %s]", fmt(f.field), f.lo, hi)
	end,
	hook = function(f)
		return string.format("HOOK          %s", f.name)
	end,
	inner_loop = function(f, indent)
		local lines = { string.format(">>INNER (max=%d):", f.max_iters) }
		for _, sub in ipairs(f.body) do
			lines[#lines + 1] = "  " .. sub:tostring(indent .. "  ")
		end
		lines[#lines + 1] = "<<END"
		return table.concat(lines, "\n" .. indent)
	end,
}

function Inst:tostring(indent)
	indent = indent or "  "
	local printer = printers[self.op]
	if printer then
		return indent .. printer(self.fields, indent)
	end
	return indent .. "?" .. self.op
end

--
-- Resource counting
--

local function max_expr_depth(expr, current_max)
	if not expr then return current_max end
	local d = expr:scratch_depth()
	return d > current_max and d or current_max
end

function M.count_resources(reg)
	local n_fields         = 0
	local n_face_fields    = 0
	local n_systems        = 0
	local max_expr_scratch = 0
	local field_list       = {} -- { name, tag, face }

	local function record(name, tag, is_face)
		field_list[#field_list + 1] = { name = name, tag = tag, face = is_face or false }
		if is_face then
			n_face_fields = n_face_fields + 1
		else
			n_fields = n_fields + 1
		end
	end

	for name, sym in pairs(reg) do
		if type(sym) ~= "table" then goto continue end

		if sym.kind == "field" then
			record(name, "field", false)
			n_systems = n_systems + 1
			if sym.eq and sym.eq._deps then
				for dep in pairs(sym.eq._deps) do
					if E.is_prev(dep) then
						record(dep, "prev", false)
					elseif E.is_expl(dep) then
						record(dep, "expl", false)
					end
				end
			end
			-- walk terms for anonymous coeff expr scratch depths
			if sym.eq and sym.eq.terms then
				for _, term in ipairs(sym.eq.terms) do
					max_expr_scratch = max_expr_depth(term.coeff, max_expr_scratch)
					max_expr_scratch = max_expr_depth(term.expr, max_expr_scratch)
				end
			end
		elseif sym.kind == "expression" then
			record(name, "expression", false)
			if sym.expr then
				local d = sym.expr:scratch_depth()
				if d > max_expr_scratch then max_expr_scratch = d end
			end
		elseif sym.kind == "intermediate" then
			local itype = sym.itype
			if itype == "face" or itype == "face_vector" then
				record(name, "face_interp", true)
			elseif itype == "grad_component" then
				record(name, "grad", false)
			elseif itype == "mwi" then
				record(name, "mwi", true)
			elseif itype == "div" or itype == "div_mwi" then
				record(name, "div", false)
			end
		end

		::continue::
	end

	table.sort(field_list, function(a, b)
		if a.face ~= b.face then return b.face end -- cell first
		return a.name < b.name
	end)

	return {
		n_fields       = n_fields,
		n_face_fields  = n_face_fields,
		n_systems      = n_systems,
		n_cell_scratch = math.max(8, max_expr_scratch + 2),
		n_face_scratch = 4,
		fields         = field_list,
	}
end

--
-- Instruction emission
--

local function emit_eval(reg, name, out)
	local sym = reg[name]
	if not sym then return end
	local itype = sym.itype or sym.kind

	if itype == "mwi" then
		out[#out + 1] = Inst.comment("rhie-chow face flux  " .. E.pretty_sym(name))
	elseif itype == "div_mwi" or itype == "div" then
		out[#out + 1] = Inst.comment("divergence  " .. E.pretty_sym(name))
	end

	if itype == "face" then
		local src_name = names.is_face(name)
		out[#out + 1] = Inst.new("face_interp_cds", {
			field = src_name, out = name })
		local src_sym = reg[src_name]
		if src_sym and src_sym.bcs and #src_sym.bcs > 0 then
			for _, bc in ipairs(src_sym.bcs) do
				out[#out + 1] = Inst.new("apply_bc_face", {
					face_field = name,
					patch      = bc.patch,
					kind       = bc.kind,
					value      = bc.value,
				})
			end
			for _, patch_name in ipairs(src_sym.unspecified_patches or {}) do
				out[#out + 1] = Inst.new("bc_placeholder", {
					field    = name,
					patch    = patch_name,
					implicit = true,
				})
			end
		else
			out[#out + 1] = Inst.new("bc_placeholder", {
				field    = name,
				patch    = nil,
				implicit = false,
			})
		end
	elseif itype == "grad" then
		local field = names.is_grad_parent(name) or ""
		out[#out + 1] = Inst.new("grad_green_gauss", {
			face_field = names.face(field),
			out_x      = names.grad(field, "x"),
			out_y      = names.grad(field, "y")
		})
	elseif itype == "mwi" then
		local U, p  = names.is_mwi(name)
		local reg_U = reg[U]
		assert(reg_U and reg_U.kind == "vector",
			"mwi: expected vector for U, got " .. tostring(U))
		local Ux, Uy = reg_U.components[1], reg_U.components[2]
		out[#out + 1] = Inst.new("rhie_chow", {
			Ux = Ux,
			Uy = Uy,
			p = p,
			grad_px = names.grad(p, "x"),
			grad_py = names.grad(p, "y"),
			ap_x = names.diag(Ux),
			ap_y = names.diag(Uy),
			out = name
		})
	elseif itype == "div_mwi" then
		local U, p = names.is_div_mwi(name)
		out[#out + 1] = Inst.new("divergence", {
			un_face = names.mwi(U, p), out = name })
	elseif itype == "div" then
		local field = names.is_div(name) or ""
		out[#out + 1] = Inst.new("divergence", {
			un_face = names.face(field), out = name })
	elseif sym.kind == "expression" then
		out[#out + 1] = Inst.new("eval_expr", { name = name, expr = sym.expr })
	end
end

---@param coeff Expr
---@param reg table
---@return table
local function coeff_of(coeff, reg)
	if not coeff then
		return { kind = "const", value = 1.0 }
	end
	if coeff.kind == "const" then
		return { kind = "const", value = coeff.value }
	end
	if coeff.kind == "sym" then
		-- check registry
		local rsym = reg and reg[coeff.name]
		if rsym and rsym.kind == "constant" then
			return { kind = "const", value = rsym.value }
		end
		return { kind = "field", name = coeff.name }
	end
	if coeff._dep_name then
		-- registered intermediate or expression - already has a field slot
		return { kind = "field", name = coeff._dep_name }
	end
	-- anonymous compound expr - needs eval_coeff before use
	return { kind = "expr", expr = coeff }
end

---Emit an eval_coeff instruction if needed
---@return string name
local function emit_coeff(coeff_desc, out)
	if coeff_desc.kind == "const" then
		return coeff_desc.value
	elseif coeff_desc.kind == "field" then
		return coeff_desc.name
	else
		out[#out + 1] = Inst.new("eval_coeff", { expr = coeff_desc.expr })
		return "__coeff"
	end
end

---@param field string
---@param term Term
---@param reg table
local function emit_term(field, term, reg, out)
	local kind = term.kind -- not term.op

	if kind == "lap" then
		---@cast term FvmLapTerm
		local c = coeff_of(term.coeff, reg)
		local harmonic = term.gamma_scheme == "HARMONIC"
		local gamma = emit_coeff(c, out)

		if type(gamma) == "number" then
			out[#out + 1] = Inst.new("laplacian_const", {
				field = field, gamma = gamma })
		else
			local scheme = harmonic and "laplacian_field_harmonic" or "laplacian_field"
			out[#out + 1] = Inst.new(scheme, {
				field = field, gamma = gamma })
		end

		if term.non_ortho then
			local gx = names.grad(field, "x")
			local gy = names.grad(field, "y")
			if type(gamma) == "number" then
				out[#out + 1] = Inst.new("laplacian_nonorth_const", {
					field = field,
					gamma = gamma,
					grad_x = gx,
					grad_y = gy
				})
			else
				out[#out + 1] = Inst.new("laplacian_nonorth_field", {
					field = field,
					gamma = gamma,
					grad_x = gx,
					grad_y = gy
				})
			end
		end
	elseif kind == "div" then
		---@cast term FvmDivTerm
		local flux_name = term.flux._dep_name
			or error("emit_term div: flux has no _dep_name", 2)
		local scheme = (term.scheme or "UDS"):lower()

		if term.coeff then
			local c = coeff_of(term.coeff, reg)
			local coeff = emit_coeff(c, out)
			out[#out + 1] = Inst.new("div_" .. scheme .. "_field", {
				field = term.phi,
				coeff = coeff,
				un_face = flux_name,
			})
		else
			out[#out + 1] = Inst.new("div_" .. scheme .. "_const", {
				field   = term.phi,
				coeff   = 1.0,
				un_face = flux_name
			})
		end

		if term.tvd then
			local limiter_op = term.tvd:lower():gsub("-", "_")

			out[#out + 1] = Inst.new("div_tvd_" .. limiter_op, {
				field   = field,
				phi     = field,
				grad_x  = names.grad(field, "x"),
				grad_y  = names.grad(field, "y"),
				un_face = flux_name
			})
		end
	elseif kind == "su" then
		---@cast term FvmSuTerm
		out[#out + 1] = Inst.new("su_integrated", { field = field, expr = term.expr })
	elseif kind == "sp" then
		---@cast term FvmSpTerm
		out[#out + 1] = Inst.new("sp_integrated", { field = field, expr = term.expr })
	elseif kind == "ddt" then
		local c = coeff_of(term.coeff, reg)
		local coeff = emit_coeff(c, out)
		local phi_prev = E.prev_name(field)

		if type(coeff) == "number" then
			out[#out + 1] = Inst.new("ddt_const", {
				field = field,
				coeff = coeff,
				phi_prev = phi_prev,
			})
		else
			out[#out + 1] = Inst.new("ddt_field", {
				field = field,
				coeff = coeff,
				phi_prev = phi_prev,
			})
		end
	end
end

local function emit_solve(reg, name, out)
	local sym = reg[name]
	assert(sym and sym.kind == "field", "emit_solve: not a field: " .. name)
	local eq = sym.eq

	out[#out + 1] = Inst.comment("solve " .. E.pretty_sym(name)
		.. "  [" .. (eq.solver or "bicgstab") .. "]")
	out[#out + 1] = Inst.new("sys_reset", { field = name })

	for _, term in ipairs(eq.terms) do
		emit_term(name, term, reg, out)
	end

	if sym.bcs and #sym.bcs > 0 then
		for _, bc in ipairs(sym.bcs) do
			out[#out + 1] = Inst.new("apply_bc_patch", {
				field = name,
				patch = bc.patch,
				kind  = bc.kind,
				value = bc.value,
			})
		end
		for _, patch_name in ipairs(sym.unspecified_patches or {}) do
			out[#out + 1] = Inst.new("bc_placeholder", {
				field    = name,
				patch    = patch_name,
				implicit = true,
			})
		end
	else
		-- No mesh context (Physics listing) or no bcs at all
		out[#out + 1] = Inst.new("bc_placeholder", {
			field    = name,
			patch    = nil,
			implicit = false,
		})
	end

	if eq.relax then
		out[#out + 1] = Inst.new("under_relax", { field = name, alpha = eq.relax })
	end

	out[#out + 1] = Inst.new("solve", {
		field     = name,
		solver    = (eq.solver or "BICGSTAB"):lower(),
		tol       = eq.tol or 1e-6,
		max_iters = eq.max_iters or 1000
	})
end

local function emit_correct(reg, name, out)
	out[#out + 1] = Inst.comment("correct " .. E.pretty_sym(name))
	local cname   = "__correct_" .. name
	local csym    = reg[cname]
	assert(csym and csym.kind == "correction",
		"emit_correct: no correction for " .. name)
	out[#out + 1] = Inst.new("apply_correction", { field = name, expr = csym.expr })
end

local function walk_steps(reg, steps, out)
	for _, step in ipairs(steps) do
		if step.op == "evaluate" then
			emit_eval(reg, step.field, out)
		elseif step.op == "solve" then
			emit_solve(reg, step.field, out)
		elseif step.op == "correct" then
			emit_correct(reg, step.field, out)
		elseif step.op == "clip" then
			out[#out + 1] = {
				op = "clip",
				field = step.field,
				lo = step.lo,
				hi = step.hi
			}
		elseif step.op == "hook" then
			out[#out + 1] = { op = "hook", fn = step.fn, name = step.name }
		elseif step.op == "inner" then
			local body = {}
			walk_steps(reg, step.inner.steps, body)
			out[#out + 1] = {
				op        = "inner_loop",
				max_iters = step.inner.max_iters,
				go_until  = step.inner.go_until,
				body      = body
			}
		end
	end
end

function M.emit_instructions(reg, expanded_alg)
	local main, post = {}, {}
	walk_steps(reg, expanded_alg.steps, main)
	if expanded_alg.post and #expanded_alg.post > 0 then
		walk_steps(reg, expanded_alg.post, post)
	end
	return main, post
end

--
-- Listings
--

function M.instruction_listing(main, post)
	local lines = { ".INSTRUCTIONS:" }
	for _, inst in ipairs(main) do
		lines[#lines + 1] = inst:tostring()
	end
	if post and #post > 0 then
		lines[#lines + 1] = ".POST:"
		for _, inst in ipairs(post) do
			lines[#lines + 1] = inst:tostring()
		end
	end
	lines[#lines + 1] = ".END"
	return table.concat(lines, "\n")
end

function M.resource_listing(res)
	local lines = {
		".RESOURCES:",
		string.format("  fields       %d", res.n_fields),
		string.format("  face_fields  %d", res.n_face_fields),
		string.format("  systems      %d", res.n_systems),
		string.format("  cell_scratch %d", res.n_cell_scratch),
		string.format("  face_scratch %d", res.n_face_scratch),
	}

	local function format_line(name, tag, target_width)
		local str = E.pretty_sym(name)
		local display_len = utf8.len(str) or #str
		local padding = math.max(0, target_width - display_len)
		return string.format("    %s%s  [%s]", str, string.rep(" ", padding), tag)
	end

	if res.fields and #res.fields > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "  .cell_fields:"
		for _, f in ipairs(res.fields) do
			if not f.face then
				lines[#lines + 1] = format_line(f.name, f.tag, 24)
			end
		end
		lines[#lines + 1] = "  .face_fields:"
		for _, f in ipairs(res.fields) do
			if f.face then
				lines[#lines + 1] = format_line(f.name, f.tag, 24)
			end
		end
	end

	lines[#lines + 1] = ".END"
	return table.concat(lines, "\n")
end

return M
