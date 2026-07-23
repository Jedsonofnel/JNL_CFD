-- [nfnl] fnl/nabla/fvm/instructions.fnl
local fvmb = require("nabla.fvm.bindings")
local chasm = require("nabla.fvm.chasm")
local _local_1_ = require("nabla.core")
local util = _local_1_.util
local function resolve_const(k)
  if ((_G.type(k) == "table") and (k.varkind == "const") and (nil ~= k.name)) then
    local name = k.name
    return name
  else
    local and_2_ = (nil ~= k)
    if and_2_ then
      local s = k
      and_2_ = util["string?"](s)
    end
    if and_2_ then
      local s = k
      return s
    else
      local and_4_ = (nil ~= k)
      if and_4_ then
        local num = k
        and_4_ = util["number?"](num)
      end
      if and_4_ then
        local num = k
        return num
      elseif (k == nil) then
        return 1
      else
        local _ = k
        return error(string.format("cannot resolve %s as a constant", k))
      end
    end
  end
end
local function resolve_rt_const(rt, k)
  local and_7_ = (nil ~= k)
  if and_7_ then
    local num = k
    and_7_ = util["number?"](num)
  end
  if and_7_ then
    local num = k
    return num
  else
    local and_9_ = (nil ~= k)
    if and_9_ then
      local s = k
      and_9_ = util["string?"](s)
    end
    if and_9_ then
      local s = k
      return chasm["get-const"](rt, s)
    else
      local _ = k
      return error(string.format("cannot resolve %s as a constant", k))
    end
  end
end
local function resolve_scalar(v)
  if ((_G.type(v) == "table") and (v.varkind == "scalar") and (v["has-sys?"] == true) and (nil ~= v.name)) then
    local name = v.name
    return name
  else
    local and_12_ = (nil ~= v)
    if and_12_ then
      local s = v
      and_12_ = util["string?"](s)
    end
    if and_12_ then
      local s = v
      return s
    else
      local _ = v
      return error(string.format("cannot resolve %s as a scalar", v))
    end
  end
end
local function make_instr(op_name, build_fn, str_fn, exec_fn)
  local entry = {build = build_fn, str = str_fn, exec = exec_fn, op = op_name}
  local function _15_(_, ...)
    local instr = build_fn(...)
    instr.op = op_name
    setmetatable(instr, {__tostring = str_fn})
    return instr
  end
  return setmetatable(entry, {__call = _15_})
end
local ASM_NAMES = {["laplacian-k"] = "LAPK", ["sys-reset-s"] = "SYSR", ["bc-close-s"] = "BCCS", ["krylov-s"] = "KRYL"}
local function simple_instr_str(op_name, ...)
  local arg_strs
  do
    local tbl_26_ = {}
    local i_27_ = 0
    for _, a in ipairs({...}) do
      local val_28_ = tostring(a)
      if (nil ~= val_28_) then
        i_27_ = (i_27_ + 1)
        tbl_26_[i_27_] = val_28_
      else
      end
    end
    arg_strs = tbl_26_
  end
  local op_asm_name = (ASM_NAMES[op_name] or "????")
  return string.format("%s %s", op_asm_name, table.concat(arg_strs, " "))
end
local function lapk_build(phi, gamma_k)
  local gamma = resolve_const(gamma_k)
  local field = resolve_scalar(phi)
  return {field = field, gamma = gamma}
end
local function lapk_str(_17_)
  local field = _17_.field
  local gamma = _17_.gamma
  return simple_instr_str("laplacian-k", field, gamma)
end
local function lapk_exec(rt, _ctx, _18_)
  local field = _18_.field
  local gamma = _18_.gamma
  local gamma0 = resolve_rt_const(rt, gamma)
  local _let_19_ = chasm["get-sys+mesh"](rt, field)
  local sys = _let_19_.sys
  local mesh = _let_19_.mesh
  return fvmb["laplacian-k!"](sys, mesh, gamma0)
end
local laplacian_k = make_instr("laplacian-k", lapk_build, lapk_str, lapk_exec)
local function bccs_build(field)
  local field0 = resolve_scalar(field)
  return {field = field0}
end
local function bccs_str(_20_)
  local field = _20_.field
  return simple_instr_str("bc-close-s", field)
end
local bc_close_tbl
local function _22_(sys, mesh, patch_name, _21_)
  local value = _21_.value
  return fvmb["patch-s-close-d!"](sys, mesh, patch_name, value)
end
local function _24_(sys, mesh, patch_name, _23_)
  local grad_n = _23_["grad-n"]
  return fvmb["patch-s-close-n!"](sys, mesh, patch_name, grad_n)
end
local function _26_(sys, mesh, patch_name, _25_)
  local a = _25_.a
  local b = _25_.b
  local c = _25_.c
  return fvmb["patch-s-close-r!"](sys, mesh, patch_name, a, b, c)
end
bc_close_tbl = {["dirichlet-s"] = _22_, ["neumann-s"] = _24_, robin = _26_}
local function bccs_exec(rt, ctx, _27_)
  local field = _27_.field
  local _let_28_ = chasm["get-sys+mesh+bcs"](rt, field)
  local sys = _let_28_.sys
  local mesh = _let_28_.mesh
  local bcs = _let_28_.bcs
  local field_spec = bcs[field]
  for patch_name, _ in pairs(mesh:patches()) do
    local spec = (field_spec[patch_name] or field_spec.__default)
    local close_fn = (bc_close_tbl[spec.kind] or error(("no bc close fn for kind: " .. spec.kind)))
    close_fn(sys, mesh, patch_name, spec)
    coroutine.yield(ctx)
  end
  return nil
end
local bc_close_s = make_instr("bc-close-s", bccs_build, bccs_str, bccs_exec)
local function sysr_build(field)
  local field0 = resolve_scalar(field)
  return {field = field0}
end
local function sysr_str(_29_)
  local field = _29_.field
  return simple_instr_str("sys-reset-s", field)
end
local function sysr_exec(rt, _ctx, _30_)
  local field = _30_.field
  local sys = chasm["get-sys"](rt, field)
  return sys:reset()
end
local sys_reset_s = make_instr("sys-reset-s", sysr_build, sysr_str, sysr_exec)
local function kryl_build(field, _3fopts)
  local field0 = resolve_scalar(field)
  local opts = (_3fopts or {})
  return {field = field0, opts = opts}
end
local function kryl_str(_31_)
  local field = _31_.field
  local opts = _31_.opts
  return simple_instr_str("krylov-s", field, (opts.solver or "bicgstab-dilu"))
end
local function make_solver(solver_name, sys, mesh, pool_cells, tol, restart)
  local case_32_ = solver_name:lower()
  if (case_32_ == "cg-jac") then
    return fvmb["new-solver-cg-jac"](sys, mesh, tol, pool_cells)
  elseif (case_32_ == "cg-dic") then
    return fvmb["new-solver-cg-dic"](sys, mesh, tol, pool_cells)
  elseif (case_32_ == "bicgstab-jac") then
    return fvmb["new-solver-bicgstab-jac"](sys, mesh, tol, pool_cells)
  elseif (case_32_ == "bicgstab-dilu") then
    return fvmb["new-solver-bicgstab-dilu"](sys, mesh, tol, pool_cells)
  elseif (case_32_ == "gmres-dilu") then
    return fvmb["new-solver-gmres-dilu"](sys, mesh, tol, pool_cells, restart)
  else
    local _ = case_32_
    return error(string.format("no solver '%s'", solver_name))
  end
end
local function krylov_iterate_21(solver, ctx, field, max_iters)
  local step = {}
  for i = 1, max_iters do
    if (step.done or step.breakdown) then break end
    local step0 = solver:iter()
    local kctx = chasm["make-inner-exec-ctx"](ctx, ("krylov:" .. field))
    kctx.iter = i
    kctx.residuals[field] = step0.residual
    kctx["rel-residuals"][field] = step0.residual
    kctx["iter-counts"][field] = i
    coroutine.yield(kctx)
    step = step0
  end
  return step
end
local function kryl_exec(rt, ctx, _34_)
  local field = _34_.field
  local opts = _34_.opts
  local _let_35_ = chasm["get-sys+mesh"](rt, field)
  local sys = _let_35_.sys
  local mesh = _let_35_.mesh
  local array = chasm["get-array"](rt, field)
  local pool_cells = chasm["get-pool-cells"](rt, field)
  local max_iters = (opts["max-iters"] or 1000)
  local tol = (opts.tol or 1e-06)
  local solver_name = (opts.solver or "bicgstab-dilu")
  local solver = make_solver(solver_name, sys, mesh, pool_cells, tol, (opts.restart or 20))
  coroutine.yield(ctx)
  local final_step = krylov_iterate_21(solver, ctx, field, max_iters)
  local change = solver:finish_change_into(array)
  ctx.changes[field] = change
  ctx.norms[field] = array:norm_l2()
  ctx.residuals[field] = (final_step and final_step.residual)
  if final_step.breakdown then
    ctx.breakdowns[field] = true
  else
  end
  return coroutine.yield(ctx)
end
local krylov_s = make_instr("krylov-s", kryl_build, kryl_str, kryl_exec)
return {["laplacian-k"] = laplacian_k, ["bc-close-s"] = bc_close_s, ["sys-reset-s"] = sys_reset_s, ["krylov-s"] = krylov_s}
