-- [nfnl] lua/nabla/fvm/chasm/vm.fnl
local program = require("nabla.fvm.chasm.program")
local VM = {}
VM.__index = VM
local function new(prog)
  return setmetatable({prog = prog}, VM)
end
local function make_exec(block_name, depth, iter)
  return {["block-name"] = block_name, depth = depth, iter = iter, status = "running", residuals = {}, ["rel-residuals"] = {}, ["iter-counts"] = {}, changes = {}, norms = {}, breakdowns = {}, ["block-end"] = false}
end
local function make_inner_exec(parent_exec, block_name)
  return {["block-name"] = block_name, depth = (parent_exec.depth + 1), iter = 0, residuals = parent_exec.residuals, ["rel-residuals"] = parent_exec["rel-residuals"], ["iter-counts"] = parent_exec["iter-counts"], changes = parent_exec.changes, norms = parent_exec.norms, breakdowns = parent_exec.breakdowns}
end
local function check_convergence(_pred, _exec)
  return false
end
local function run_outer_iter_21(__3fblock, __3fdepth)
  return error("this is a forward declaration")
end
local function run_block_21(block, exec, depth)
  for _, inst in ipairs(block.instructions) do
    if inst.instructions then
      run_outer_iter_21(inst, (1 + depth))
    else
      block.prog.ISA[inst.op].dispatch(block.prog, exec, inst)
    end
    coroutine.yield(exec)
  end
  return nil
end
local function run_outer_iter_210(block, _3fdepth, _3fiter)
  local iter = (_3fiter or 1)
  local depth = (_3fdepth or 1)
  local exec = make_exec(block.name, depth, iter)
  run_block_21(block, exec, depth)
  if (check_convergence(block.convergence, exec) or (block.iters <= iter)) then
    return exec
  else
    return run_outer_iter_210(block, depth, (1 + iter))
  end
end
local function start_21(vm)
  program["allocate!"](vm.prog)
  local function _3_()
    run_outer_iter_210(vm.prog["main-block"], 1)
    return coroutine.yield({status = "done"})
  end
  vm.co = coroutine.create(_3_)
  return nil
end
local function step_21(vm)
  if not vm.co then
    return {status = "error", error = "VM not started"}
  else
    local ok, exec = coroutine.resume(vm.co)
    if not ok then
      return {status = "error", error = exec}
    else
      return exec
    end
  end
end
local function run_all_21(vm)
  local function loop(result)
    if (result.status == "running") then
      return loop(step_21(result))
    else
      if (result.status == "error") then
        return error(("VM running error: " .. result.error))
      else
        return result
      end
    end
  end
  return loop(step_21(vm))
end
VM.start = function(self)
  return start_21(self)
end
VM.step = function(self)
  return step_21(self)
end
VM.run_all = function(self)
  return run_all_21(self)
end
return {new = new, ["make-exec"] = make_exec, ["make-inner-exec"] = make_inner_exec, ["start!"] = start_21, ["step!"] = step_21, ["run-all!"] = run_all_21}
