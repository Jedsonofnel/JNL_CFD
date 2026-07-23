-- [nfnl] fnl/nabla/fvm/chasm-original/isa.fnl
local fvmb = require("nabla.fvm.bindings")
local _local_1_ = require("nabla.util")
local number_3f = _local_1_["number?"]
local vm = require("nabla.fvm.chasm.vm")
local function assert_same_domain(op_name, ...)
  local fields = {...}
  local domain = fields[1]["domain-name"]
  local same_3f
  do
    local same_3f0 = true
    for _, field in ipairs(fields) do
      if not same_3f0 then break end
      same_3f0 = (field["domain-name"] == domain)
    end
    same_3f = same_3f0
  end
  if not same_3f then
    return error(string.format("%s input vars need to belong to the same domain", op_name))
  else
    return nil
  end
end
local function get_const(op_name, k, default)
  if ((_G.type(k) == "table") and (nil ~= k.value)) then
    local value = k.value
    return value
  else
    local and_3_ = (nil ~= k)
    if and_3_ then
      local num = k
      and_3_ = number_3f(num)
    end
    if and_3_ then
      local num = k
      return num
    elseif (k == nil) then
      return (default or 1)
    else
      local _ = k
      return error(string.format("%s: expects a constant", op_name))
    end
  end
end
local function get_scalar(prog, op_name, v)
  local v0 = prog["get-var"](prog, v)
  if (v0.rank ~= 0) then
    error(string.format("%s: '%s' must be a scalar", op_name, v0.name))
  else
  end
  return v0
end
local function get_scalars(prog, op_name, ...)
  local resolved
  do
    local tbl_26_ = {}
    local i_27_ = 0
    for _, v in ipairs({...}) do
      local val_28_ = get_scalar(prog, op_name, v)
      if (nil ~= val_28_) then
        i_27_ = (i_27_ + 1)
        tbl_26_[i_27_] = val_28_
      else
      end
    end
    resolved = tbl_26_
  end
  return resolved
end
local function get_prog(program, op_name, field)
  local v = get_scalar(program, op_name, field)
  if not v["has-sys?"] then
    error(string.format("%s: '%s' must be prognostic (have a linalg system)", op_name, v.name))
  else
  end
  return v
end
local face_norm_cw = {}
face_norm_cw.build = function(block, w, xc, yc)
  local _let_9_ = get_scalars(block.prog, "face-norm-cw", w, xc, yc)
  local w0 = _let_9_[1]
  local xc0 = _let_9_[2]
  local yc0 = _let_9_[3]
  assert_same_domain("face-norm-cw", w0, xc0, yc0)
  return {w = w0, xc = xc0, yc = yc0}
end
face_norm_cw.str = function(_10_)
  local w = _10_.w
  local xc = _10_.xc
  local yc = _10_.yc
  return string.format("face normal cw %s %s %s", w, xc, yc)
end
face_norm_cw.dispatch = function(prog, _exec, _11_)
  local w = _11_.w
  local xc = _11_.xc
  local yc = _11_.yc
  local _let_12_ = get_scalars(prog, "face-norm-cw", w, xc, yc)
  local w0 = _let_12_[1]
  local xc0 = _let_12_[2]
  local yc0 = _let_12_[3]
  local _let_13_ = prog.domains[w0["domain-name"]]
  local mesh = _let_13_.mesh
  local pools = _let_13_.pools
  return fvmb["face-norm-cw"](mesh, w0.array, xc0.array, yc0.array, pools.face)
end
local laplacian_k = {}
laplacian_k.build = function(block, phi, gamma_k)
  local field = get_scalar(block.prog, "laplacian-k", phi)
  local gamma = get_const("laplacian-k", gamma_k)
  return {field = field, gamma = gamma}
end
laplacian_k.str = function(_14_)
  local field = _14_.field
  local gamma = _14_.gamma
  return string.format("laplacian constant-gamma %s %g", field.name, gamma)
end
laplacian_k.dispatch = function(prog, _exec, _15_)
  local field = _15_.field
  local gamma = _15_.gamma
  local field0 = get_scalar(prog, "laplacian-k", field)
  local gamma0 = get_const("laplacian-k", gamma)
  local _let_16_ = prog.domains[field0["domain-name"]]
  local mesh = _let_16_.mesh
  return fvmb["laplacian-k"](field0.fvsys, mesh, gamma0)
end
local bc_close_s = {}
bc_close_s.build = function(block, field)
  local field0 = get_prog(block.prog, "bc-close-s", field)
  return {field = field0}
end
bc_close_s.str = function(_17_)
  local field = _17_.field
  return string.format("close BCs scalar %s", field.name)
end
local bc_close_tbl = {}
bc_close_tbl["dirichlet-s"] = function(sys, mesh, patch_name, _18_)
  local value = _18_.value
  return fvmb["patch-s-close-d"](sys, mesh, patch_name, value)
end
bc_close_tbl["neumann-s"] = function(sys, mesh, patch_name, _19_)
  local grad_n = _19_["grad-n"]
  return fvmb["patch-s-close-n"](sys, mesh, patch_name, grad_n)
end
bc_close_tbl["robin-s"] = function(sys, mesh, patch_name, _20_)
  local a = _20_.a
  local b = _20_.b
  local c = _20_.c
  return fvmb["patch-s-close-r"](sys, mesh, patch_name, a, b, c)
end
bc_close_s.dispatch = function(prog, exec, _21_)
  local field = _21_.field
  local field0 = get_prog(prog, "bc-close-s", field)
  local _let_22_ = prog.domains[field0["domain-name"]]
  local mesh = _let_22_.mesh
  local bcs = _let_22_.bcs
  local field_spec = bcs[field0.name]
  for _, patch in ipairs(mesh:patches()) do
    local spec = (field_spec[patch.name] or field_spec.__default)
    local close_fn = (bc_close_tbl[spec.kind] or error(("could not find bc close fn for kind: " .. spec.kind)))
    close_fn(field0.fvsys, mesh, patch.name, spec)
    coroutine.yield(exec)
  end
  return nil
end
local sys_reset_s = {}
sys_reset_s.build = function(block, field)
  local field0 = get_prog(block.prog, "sys-reset-s", field)
  return {field = field0}
end
sys_reset_s.str = function(_23_)
  local field = _23_.field
  return string.format("system reset %s", field.name)
end
sys_reset_s.dispatch = function(prog, _exec, _24_)
  local field = _24_.field
  local _let_25_ = get_prog(prog, "sys-reset-s", field)
  local fvsys = _let_25_.fvsys
  return fvsys:reset()
end
local krylov_s = {}
krylov_s.build = function(block, field, _3fopts)
  local field0 = get_prog(block.prog, "krylov-s", field)
  local opts = (_3fopts or {})
  return {field = field0, opts = opts}
end
krylov_s.str = function(_26_)
  local field = _26_.field
  local opts = _26_.opts
  return string.format("krylov solve for %s TODO OPTS", field.name)
end
local function make_solver(solver_name, sys, field, pool_cw, opts)
  local tol = (opts or 1e-06)
  local restart = (opts.restart or 20)
  local case_27_ = solver_name:lower()
  if (case_27_ == "cg-jac") then
    return fvmb["new-solver-cg-jac"](sys, field, tol, pool_cw)
  elseif (case_27_ == "cg-dic") then
    return fvmb["new-solver-cg-dic"](sys, field, tol, pool_cw)
  elseif (case_27_ == "bicgstab-jac") then
    return fvmb["new-solver-bicgstab-jac"](sys, field, tol, pool_cw)
  elseif (case_27_ == "bicgstab-dilu") then
    return fvmb["new-solver-bicgstab-dilu"](sys, field, tol, pool_cw)
  elseif (case_27_ == "gmres-dilu") then
    return fvmb["new-solver-gmres-dilu"](sys, field, tol, pool_cw, restart)
  else
    local _ = case_27_
    return error(string.format("Could not make solver '%s', not an available option", solver_name))
  end
end
local function krylov_iterate_21(solver, exec, field, max_iters)
  local step = {}
  for i = 1, max_iters do
    if (step.done or step.breakdown) then break end
    local step0 = solver:iter()
    local kexec = vm["make-inner-exec"](exec, ("krylov:" .. field.name))
    kexec.iter = i
    kexec.residuals[field.name] = step0.residual
    kexec["rel-residuals"][field.name] = step0.residual
    kexec["iter-counts"][field.name] = i
    coroutine.yield(kexec)
    step = step0
  end
  return step
end
local function krylov_finish_21(solver, exec, field, final_step)
  local change = solver:finish_change_into(field.array)
  exec.changes[field.name] = change
  exec.norms[field.name] = field.array:norm_l2()
  exec.residuals[field.name] = (final_step and final_step.residual)
  if final_step.breakdown then
    exec.breakdowns[field.name] = true
    return nil
  else
    return nil
  end
end
krylov_s.dispatch = function(prog, exec, _30_)
  local field = _30_.field
  local opts = _30_.opts
  local field0 = get_prog(prog, "krylov-s", field)
  local domain = prog.domains[field0["domain-name"]]
  local max_iters = (opts["max-iters"] or 1000)
  local solver_name = (opts.solver or "bicgstab-dilu")
  local solver = make_solver(solver_name, field0.fvsys, domain["pool-cell"], opts)
  coroutine.yield(exec)
  local final_step = krylov_iterate_21(solver, exec, field0, max_iters)
  krylov_finish_21(solver, exec, field0, final_step)
  return coroutine.yield(exec)
end
return {["face-norm-cw"] = face_norm_cw, ["laplacian-k"] = laplacian_k, ["bc-close-s"] = bc_close_s, ["sys-reset-s"] = sys_reset_s, ["krylov-s"] = krylov_s}
