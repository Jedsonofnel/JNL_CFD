-- jnl/fvm/instruction.lua

-- deps
local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")

---@class Inst
---@field op string
---@field fields table
local Inst = {}
Inst.__index = Inst

local function new(op, fields)
	return setmetatable({ op = op, fields = fields or {} }, Inst)
end

function Inst.new(op, fields)
	return new(op, fields)
end

function Inst:__index(k)
	if Inst[k] then return Inst[k] end
	return self.fields[k]
end

function Inst:__newindex(k, v)
	self.fields[k] = v
end

--
-- Config
--

local INST_DEFAULTS = {
	grad      = "gg", -- "gg" (Green-Gauss) | "lsq" (least-squares)
	div       = "uds", -- "uds" | "cds" | "tvd"
	non_ortho = true,
	relax     = 1.0,
	solver    = "BICGSTAB_DILU",
	tol       = 1e-6,
	max_iters = 100,
}

local Cfg = {}
Cfg.__index = Cfg

---@param fields table?  per-field config  (config.fields from Alg)
---@param default table?  algorithm-wide defaults (config.default from Alg)
function Cfg.new(fields, default)
	return setmetatable({ _f = fields or {}, _d = default or {} }, Cfg)
end

---Hierarchical lookup: field-specific → alg-default → INST_DEFAULTS
---@param field string   field name, or "default" to skip per-field lookup
---@param key   string   config key
function Cfg:get(field, key)
	if field ~= "default" then
		local fc = self._f[field]
		if fc and fc[key] ~= nil then return fc[key] end
	end
	local dc = self._d[key]
	if dc ~= nil then return dc end
	return INST_DEFAULTS[key]
end

local default_cfg = Cfg.new()

--
-- Constructors: abstract instructions (high level)
--

---@param text string?
function Inst.comment(text)
	return new("comment", { text = text or "", level = "abstract" })
end

---@param text string?
function Inst.section(text)
	return new("comment", {
		text = text or "",
		section = true,
		level = "concrete",
	})
end

---@param field string
---@param value number
function Inst.fill(field, value)
	return new("fill", { field = field, value = value, level = "abstract" })
end

---@param field string
---@param implicit boolean? True for compiler-inserted evaluates; false for user-scheduled evaluates.
function Inst.evaluate(field, implicit)
	if implicit == nil then implicit = true end
	return new("evaluate", { field = field, implicit = implicit, level = "abstract" })
end

function Inst.solve(field)
	return new("solve", { field = field, level = "abstract" })
end

function Inst.correct(field)
	return new("correct", { field = field, level = "abstract" })
end

function Inst.clip(field, lo, hi)
	hi = hi or math.huge
	return new("clip", { field = field, lo = lo, hi = hi, level = "abstract" })
end

function Inst.zero(field)
	return new("zero", { field = field, level = "abstract" })
end

--
-- Constructors: explicit evaluation instructions
--

function Inst.eval_expr(field, node)
	return new("eval_expr", { field = field, node = node })
end

-- anonymous evaluation of coeff into a scratch
function Inst.eval_coeff(node)
	return new("eval_coeff", { node = node })
end

---evaluates correction node expression into delta and does field:axpy(1, delta)
function Inst.apply_correction(field, node)
	return new("apply_correction", { field = field, node = node })
end

function Inst.face_interp(field, out)
	return new("face_interp", { field = field, out = out })
end

function Inst.face_normal(ux_face, uy_face, out)
	return new("face_normal", { ux_face = ux_face, uy_face = uy_face, out = out })
end

function Inst.face_normal_c(ux, uy, out)
	return new("face_normal_c", { ux = ux, uy = uy, out = out })
end

-- Gradient from a field (green gauss vs lsq is a policy)
function Inst.grad(field, out_x, out_y)
	return new("grad", { field = field, out_x = out_x, out_y = out_y })
end

-- sum a face-normal scalar field over faces -> cell scalar
function Inst.divergence(face_normal_field, out)
	return new("divergence", { flux = face_normal_field, out = out })
end

-- divergence from cell vector components - calls jnl_divergence_i_c / jnl_divergence_v_c
function Inst.divergence_c(field, ux, uy, integrated)
	return new("divergence_c", {
		field      = field,
		ux         = ux,
		uy         = uy,
		integrated = integrated ~= false,
	})
end

-- Rhie-Chow face-normal velocity
function Inst.rhie_chow(Ux, Uy, p, grad_px, grad_py, diag_x, diag_y, out)
	return new("rhie_chow", {
		Ux = Ux,
		Uy = Uy,
		p = p,
		grad_px = grad_px,
		grad_py = grad_py,
		diag_x = diag_x,
		diag_y = diag_y,
		out = out,
	})
end

--
-- Constructors: Linear algebra instructions
--

function Inst.sys_reset(field)
	return new("sys_reset", { field = field })
end

function Inst.diag_snapshot(field, out)
	return new("diag_snapshot", { field = field, out = out })
end

function Inst.under_relax(field)
	V.identifier(field, "Inst.under_relax field")
	return new("under_relax", { field = field })
end

function Inst.solve_linalg(field)
	return new("solve_linalg", { field = field })
end

--
-- Constructors: FVM assembly operators
--

---@param field string
---@param rho number
---@param expr Node? Optional rho-expr for display
function Inst.ddt_k(field, rho, expr)
	return new("ddt_k", { field = field, coeff = rho, node = expr })
end

---@param field string
---@param rho string Name of rho field
---@param expr Node? Optional rho-expr for display
function Inst.ddt_f(field, rho, expr)
	return new("ddt_f", { field = field, coeff = rho, node = expr })
end

---@param field string
---@param gamma number
---@param expr Node? Optional gamma-expr for display
function Inst.lap_k(field, gamma, expr)
	return new("lap_k", { field = field, coeff = gamma, node = expr })
end

---@param field string
---@param gamma string
---@param expr Node?
function Inst.lap_f(field, gamma, expr)
	return new("lap_f", { field = field, coeff = gamma, node = expr })
end

---@param field string
---@param grad_x string
---@param grad_y string
---@param coeff number
---@param expr Node?
function Inst.lap_nonorth_k(field, grad_x, grad_y, coeff, expr)
	return new("lap_nonorth_k", { field = field, grad_x = grad_x, grad_y = grad_y, coeff = coeff, node = expr })
end

---@param field string
---@param grad_x string
---@param grad_y string
---@param coeff string
---@param expr Node?
function Inst.lap_nonorth_f(field, grad_x, grad_y, coeff, expr)
	return new("lap_nonorth_f", { field = field, grad_x = grad_x, grad_y = grad_y, coeff = coeff, node = expr })
end

---Implicit UDS/CDS convection assembly with constant coefficient (rho)
---@param field string
---@param flux string
---@param coeff number
function Inst.div_k(field, flux, coeff)
	return new("div_k", { field = field, flux = flux, coeff = coeff })
end

---Implicit UDS/CDS convection assembly with named field coefficient.
---@param field string
---@param flux string
---@param coeff string
---@param expr Node?
function Inst.div_f(field, flux, coeff, expr)
	return new("div_f", { field = field, flux = flux, coeff = coeff, node = expr })
end

---Explicit deferred correction RHS contribution.
---runner no-ops if alg:cfg(field, "div") == "uds"|"cds"
---@param field string
---@param flux string
---@param grad_x string
---@param grad_y string
function Inst.div_dc(field, flux, grad_x, grad_y)
	return new("div_dc", { field = field, flux = flux, grad_x = grad_x, grad_y = grad_y })
end

---@param field string
---@param coeff number
---@param volumetric boolean
function Inst.su_k(field, coeff, volumetric)
	return new("su_k", { field = field, coeff = coeff, volumetric = volumetric })
end

---@param field string
---@param coeff string
---@param volumetric boolean
---@param expr Node?
function Inst.su_f(field, coeff, volumetric, expr)
	return new("su_f", { field = field, coeff = coeff, volumetric = volumetric, node = expr })
end

---@param field     string
---@param scale     number   scalar multiplier (negative to subtract)
---@param src       string   name of source cell field
---@param volumetric boolean default true
---@param expr Node?
function Inst.su_fs(field, scale, src, volumetric, expr)
	return new("su_fs", {
		field      = field,
		scale      = scale,
		src        = src,
		volumetric = volumetric ~= false,
		node       = expr,
	})
end

---@param field string
---@param coeff number
---@param volumetric boolean
function Inst.sp_k(field, coeff, volumetric)
	return new("sp_k", { field = field, coeff = coeff, volumetric = volumetric })
end

---@param field string
---@param coeff string
---@param volumetric boolean
---@param expr Node?
function Inst.sp_f(field, coeff, volumetric, expr)
	return new("sp_f", { field = field, coeff = coeff, volumetric = volumetric, node = expr })
end

---@param field     string
---@param scale     number
---@param src       string
---@param volumetric boolean default true
---@param expr Node?
function Inst.sp_fs(field, scale, src, volumetric, expr)
	return new("sp_fs", {
		field      = field,
		scale      = scale,
		src        = src,
		volumetric = volumetric ~= false,
		node       = expr,
	})
end

--
-- Patch scalar ghost fill
--

---@param field string
---@param patch string
---@param value number
function Inst.pfill_s_d(field, patch, value)
	return new("patch_s_fill_d", { field = field, patch = patch, value = value })
end

---@param field string
---@param patch string
---@param grad_n number
function Inst.pfill_s_n(field, patch, grad_n)
	return new("patch_s_fill_n", { field = field, patch = patch, grad_n = grad_n })
end

---@param field string
---@param patch string
---@param a number
---@param b number
---@param c number
function Inst.pfill_s_r(field, patch, a, b, c)
	return new("patch_s_fill_r", { field = field, patch = patch, a = a, b = b, c = c })
end

--
-- Patch scalar implicit close
--

---@param field string
---@param patch string
---@param value number
function Inst.pclose_s_d(field, patch, value)
	return new("patch_s_close_d", { field = field, patch = patch, value = value })
end

---@param field string
---@param patch string
---@param grad_n number
function Inst.pclose_s_n(field, patch, grad_n)
	return new("patch_s_close_n", { field = field, patch = patch, grad_n = grad_n })
end

---@param field string
---@param patch string
---@param a number
---@param b number
---@param c number
function Inst.pclose_s_r(field, patch, a, b, c)
	return new("patch_s_close_r", { field = field, patch = patch, a = a, b = b, c = c })
end

--
-- Patch vector ghost fill
--

---@param ux string
---@param uy string
---@param patch string
---@param ux_val number
---@param uy_val number
function Inst.pfill_v_d(ux, uy, patch, ux_val, uy_val)
	return new("patch_v_fill_d", {
		ux = ux,
		uy = uy,
		patch = patch,
		ux_val = ux_val,
		uy_val = uy_val
	})
end

---@param ux string
---@param uy string
---@param patch string
---@param ux_gn number
---@param uy_gn number
function Inst.pfill_v_n(ux, uy, patch, ux_gn, uy_gn)
	return new("patch_v_fill_n", {
		ux = ux,
		uy = uy,
		patch = patch,
		ux_gn = ux_gn,
		uy_gn = uy_gn
	})
end

---@param ux string
---@param uy string
---@param patch string
---@param nkind number
---@param nval number
---@param tkind number
---@param tval number
function Inst.pfill_v_nt(ux, uy, patch, nkind, nval, tkind, tval)
	return new("patch_v_fill_nt", {
		ux = ux,
		uy = uy,
		patch = patch,
		nkind = nkind,
		nval = nval,
		tkind = tkind,
		tval = tval
	})
end

--
-- Display: abstract instruction formatting
--

-- dispatch table
local abstract_fmt = {}

function abstract_fmt.comment(f)
	local prefix = f.section and "\n;; " or ";; "
	return prefix .. (f.text or "")
end

function abstract_fmt.fill(f)
	return string.format("  FILL       %-14s %g", f.field, f.value or 0)
end

function abstract_fmt.evaluate(f)
	return string.format("%s EVALUATE  %s", f.implicit and "~" or "*", f.field)
end

function abstract_fmt.solve(f)
	local tag = f.tag and ("  [" .. f.tag .. "]") or ""
	return string.format("* SOLVE      %s%s", f.field, tag)
end

function abstract_fmt.correct(f)
	return string.format("* CORRECT    %s", f.field)
end

function abstract_fmt.clip(f)
	local hi = f.hi == math.huge and G.inf or string.format("%g", f.hi)
	return string.format("~ CLIP       %s  [%g, %s]", f.field, f.lo, hi)
end

function abstract_fmt.zero(f)
	return string.format("* ZERO       %s", f.field)
end

--
-- Display: concrete instruction formatting
--

-- Prefer the Nabla node's pretty-print over the raw (potentially mangled)
-- coefficient field name.  f.node is set by the lowering pass whenever the
-- coefficient came from a field or expression; tostring(Node) calls
-- nabla.pretty and renders human-readable maths.
local function coeff_str(f)
	if f.node then return tostring(f.node) end
	return tostring(f.coeff)
end

-- source field: prefer node pretty-print over raw field name
local function src_str(f)
	if f.node then return tostring(f.node) end
	return tostring(f.src or f.coeff)
end

-- scaled source: absorbs scale=±1 cleanly
local function scaled_src_str(f)
	local s  = src_str(f)
	local sc = f.scale
	if sc == 1.0 then return s end
	if sc == -1.0 then return "(-" .. s .. ")" end
	return string.format("(%+.6g * %s)", sc, s)
end

local concrete_fmt = {}

-- infrastructure

function concrete_fmt.comment(f)
	local prefix = f.section and "\n;; " or ";; "
	return prefix .. (f.text or "")
end

function concrete_fmt.sys_reset(f, _)
	return string.format("SYS_RESET     %s", f.field)
end

function concrete_fmt.zero(f, _)
	return string.format("ZERO          %s", f.field)
end

function concrete_fmt.fill(f, _)
	return string.format("FILL          %-16s %g", f.field, f.value or 0)
end

function concrete_fmt.eval_expr(f, _)
	return string.format("EVAL_EXPR     %s", f.field)
end

-- eval_coeff always has a node (that's its whole job)
function concrete_fmt.eval_coeff(f, _)
	return string.format("EVAL_COEFF    %s", tostring(f.node))
end

function concrete_fmt.apply_correction(f, _)
	return string.format("CORRECT       %s <- %s", f.field, tostring(f.node))
end

function concrete_fmt.diag_snapshot(f, _)
	return string.format("DIAG_SNAPSHOT %s -> %s", f.field, f.out)
end

function concrete_fmt.under_relax(f, cfg)
	local alpha = cfg:get(f.field, "relax")
	return string.format("UNDER_RELAX   %s  alpha=%g", f.field, alpha)
end

function concrete_fmt.solve_linalg(f, _)
	return string.format("SOLVE         %s", f.field)
end

-- field / face ops

function concrete_fmt.face_interp(f, _)
	return string.format("FACE_INTERP   %s -> %s", f.field, f.out)
end

function concrete_fmt.face_normal(f, _)
	return string.format("FACE_NORMAL   (%s,%s) -> %s", f.ux_face, f.uy_face, f.out)
end

function concrete_fmt.face_normal_c(f, _)
	return string.format("FACE_NORMAL_C (%s,%s) -> %s", f.ux, f.uy, f.out)
end

function concrete_fmt.divergence(f, _)
	local mode = f.integrated and "[i]" or "[v]"
	return string.format("DIVERGENCE %-4s %s -> %s",
		mode, f.flux, f.out)
end

function concrete_fmt.divergence_c(f, _)
	local mode = f.integrated and "[i]" or "[v]"
	return string.format("DIVERGENCE_C %-4s (%s,%s) -> %s",
		mode, f.ux, f.uy, f.field)
end

function concrete_fmt.rhie_chow(f, _)
	return string.format("RHIE_CHOW     (%s,%s)  p=%s -> %s", f.Ux, f.Uy, f.p, f.out)
end

-- gradient: reconstruction method comes from cfg
function concrete_fmt.grad(f, cfg)
	local method = cfg:get(f.field, "grad"):upper() -- "GG" or "LSQ"
	return string.format("GRAD [%-3s]    %s -> (%s,%s)", method, f.field, f.out_x, f.out_y)
end

-- ddt

function concrete_fmt.ddt_k(f, _)
	return string.format("DDT_K         %s  rho=%g", f.field, f.coeff)
end

function concrete_fmt.ddt_f(f, _)
	return string.format("DDT_F         %s  rho=%s", f.field, coeff_str(f))
end

-- laplacian
-- Non-ortho correction is always emitted as a separate instruction by the
-- lowering pass, so base lap lines carry no annotation for it.

function concrete_fmt.lap_k(f, _)
	return string.format("LAP_K         %s  gamma=%g", f.field, f.coeff)
end

function concrete_fmt.lap_f(f, _)
	return string.format("LAP_F         %s  gamma=%s", f.field, coeff_str(f))
end

-- Returns nil (suppressed) when non_ortho is disabled: runner already no-ops
-- these, so there's no point cluttering the listing with dead instructions.
function concrete_fmt.lap_nonorth_k(f, cfg)
	if not cfg:get(f.field, "non_ortho") then return nil end
	return string.format("LAP_NONORTH_K %s  gamma=%g  grad=(%s,%s)",
		f.field, f.coeff, f.grad_x, f.grad_y)
end

function concrete_fmt.lap_nonorth_f(f, cfg)
	if not cfg:get(f.field, "non_ortho") then return nil end
	return string.format("LAP_NONORTH_F %s  gamma=%s  grad=(%s,%s)",
		f.field, coeff_str(f), f.grad_x, f.grad_y)
end

-- convection

function concrete_fmt.div_k(f, cfg)
	local scheme = cfg:get(f.field, "div"):upper()
	return string.format("DIV_K [%s]    %s  flux=%s  rho=%g",
		scheme, f.field, f.flux, f.coeff)
end

function concrete_fmt.div_f(f, cfg)
	local scheme = cfg:get(f.field, "div"):upper()
	return string.format("DIV_F [%s]    %s  flux=%s  rho=%s",
		scheme, f.field, f.flux, coeff_str(f))
end

-- Deferred correction is a no-op in the runner for UDS/CDS, so suppress the
-- line entirely when the scheme isn't TVD — matches runner behaviour exactly.
function concrete_fmt.div_dc(f, cfg)
	if cfg:get(f.field, "div") ~= "tvd" then return nil end
	return string.format("DIV_DC        %s  flux=%s  grad=(%s,%s)",
		f.field, f.flux, f.grad_x, f.grad_y)
end

-- source terms
-- Discriminated _k / _f; volumetric vs integrated shown inline so the reader
-- knows whether this is already *V or needs cell-volume weighting.

function concrete_fmt.su_k(f, _)
	local tag = f.volumetric and "[vol]" or "[int]"
	return string.format("SU_K  %-4s    %s  src=%g", tag, f.field, f.coeff)
end

function concrete_fmt.su_f(f, _)
	local tag = f.volumetric and "[vol]" or "[int]"
	return string.format("SU_F  %-4s    %s  src=%s", tag, f.field, src_str(f))
end

function concrete_fmt.su_fs(f, _)
	local tag = f.volumetric and "[vol]" or "[int]"
	return string.format("SU_FS %-4s    %s  src=%s", tag, f.field, scaled_src_str(f))
end

function concrete_fmt.sp_k(f, _)
	local tag = f.volumetric and "[vol]" or "[int]"
	return string.format("SP_K  %-4s    %s  src=%g", tag, f.field, f.coeff)
end

function concrete_fmt.sp_f(f, _)
	local tag = f.volumetric and "[vol]" or "[int]"
	return string.format("SP_F  %-4s    %s  src=%s", tag, f.field, src_str(f))
end

function concrete_fmt.sp_fs(f, _)
	local tag = f.volumetric and "[vol]" or "[int]"
	return string.format("SP_FS %-4s    %s  src=%s", tag, f.field, scaled_src_str(f))
end

-- patch: scalar ghost fill

function concrete_fmt.patch_s_fill_d(f, _)
	return string.format("PFILL_S_D     %s@%s  val=%g", f.field, f.patch, f.value)
end

function concrete_fmt.patch_s_fill_n(f, _)
	return string.format("PFILL_S_N     %s@%s  grad_n=%g", f.field, f.patch, f.grad_n)
end

function concrete_fmt.patch_s_fill_r(f, _)
	return string.format("PFILL_S_R     %s@%s  a=%g b=%g c=%g",
		f.field, f.patch, f.a, f.b, f.c)
end

-- patch: scalar implicit close

function concrete_fmt.patch_s_close_d(f, _)
	return string.format("PCLOSE_S_D    %s@%s  val=%g", f.field, f.patch, f.value)
end

function concrete_fmt.patch_s_close_n(f, _)
	return string.format("PCLOSE_S_N    %s@%s  grad_n=%g", f.field, f.patch, f.grad_n)
end

function concrete_fmt.patch_s_close_r(f, _)
	return string.format("PCLOSE_S_R    %s@%s  a=%g b=%g c=%g",
		f.field, f.patch, f.a, f.b, f.c)
end

-- patch: vector ghost fill

function concrete_fmt.patch_v_fill_d(f, _)
	return string.format("PFILL_V_D     (%s,%s)@%s  val=(%g,%g)",
		f.ux, f.uy, f.patch, f.ux_val, f.uy_val)
end

function concrete_fmt.patch_v_fill_n(f, _)
	return string.format("PFILL_V_N     (%s,%s)@%s  gn=(%g,%g)",
		f.ux, f.uy, f.patch, f.ux_gn, f.uy_gn)
end

function concrete_fmt.patch_v_fill_nt(f, _)
	local bk = { [0] = "N", [1] = "D", [2] = "R" }
	return string.format("PFILL_V_NT    (%s,%s)@%s  n:%s=%g  t:%s=%g",
		f.ux, f.uy, f.patch,
		bk[f.nkind] or "?", f.nval,
		bk[f.tkind] or "?", f.tval)
end

--
-- Display: Inst tostring methods
--

function Inst:tostring_abstract(indent)
	indent = indent or ""
	local fn = abstract_fmt[self.op]
	if fn then return indent .. fn(self.fields) end
	return nil
end

---@param indent string?
---@param cfg    table?    falls back to INST_DEFAULTS if nil
function Inst:tostring(indent, cfg)
	indent   = indent or "  "
	cfg      = cfg or default_cfg
	local fn = concrete_fmt[self.op]
	if not fn then return indent .. "?" .. self.op end
	local s = fn(self.fields, cfg)
	if s == nil then return nil end
	return indent .. s
end

function Inst:__tostring()
	return self:tostring() or ("  ?" .. self.op)
end

-- Export Cfg so algorithm.lua can build typed config objects
Inst.Cfg         = Cfg
Inst.DEFAULTS    = INST_DEFAULTS
Inst.default_cfg = default_cfg

return Inst
