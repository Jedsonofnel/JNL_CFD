-- jnl/fvm/chasm/vm.lua - CHASM virtual machine and execution ctx
-- <jed@nelson.ac> // 2026-07-19

---@class CHASMvm
---@field prog CHASMprogram
---@field co thread
local VM = {}
VM.__index = VM

---@param prog CHASMprogram
---@return CHASMvm
local function new_vm(prog)
    return setmetatable({
        prog = prog,
    }, VM)
end

--
-- exec state object
--

---@param block_name string
---@param depth number
---@param iter number
local function make_exec(block_name, depth, iter)
    return {
        block_name = block_name,
        depth = depth,
        iter = iter,
        status = "running",
        block_end = false,
        residuals = {},
        rel_residuals = {},
        iter_counts = {},
        changes = {},
        norms = {},
        breakdowns = {},
    }
end

local function make_inner_exec(parent_exec, block_name)
    local e = make_exec(block_name, parent_exec.depth + 1, 0)
    -- share diagnostic tables by reference
    e.residuals = parent_exec.residuals
    e.rel_residuals = parent_exec.rel_residuals
    e.iter_counts = parent_exec.iter_counts
    e.changes = parent_exec.changes
    e.norms = parent_exec.norms
    e.breakdowns = parent_exec.breakdowns
    return e
end

--
-- Execution
--

-- TODO implement this
local function check_converge(pred, exec)
    return false
end

---@param block CHASMblock
---@param depth integer?
local function run_block(block, depth)
    depth = depth or 1

    for iter = 1, block.iters do
        local exec = make_exec(block.name, depth, iter)

        for _, instr in ipairs(block.instructions) do
            if instr.instructions then -- is a block
                run_block(instr, depth + 1)
            else
                local dispatch_fn = block.prog.ISA[instr.op].dispatch
                dispatch_fn(block.prog, exec, instr)
            end
            coroutine.yield(exec)
        end
        if check_converge(block.converge, exec) then
            break
        end
    end
end

--
-- Public API
--

function VM:start()
    self.prog:allocate()
    self.co = coroutine.create(function()
        run_block(self.prog.main_block, 1)

        -- final yield so caller sees done
        coroutine.yield({ status = "done" })
    end)
    return self
end

function VM:step()
    if not self.co then
        return { status = "error", error = "VM not started" }
    end
    local ok, exec = coroutine.resume(self.co)
    if not ok then
        return { status = "error", error = exec }
    end
    return exec
end

function VM:run_all()
    local result = self:step()
    while result.status == "running" do
        result = self:step()
    end

    if result.status == "error" then
        error("VM running error: " .. result.error)
    end
    return result
end

return {
    new = new_vm,
    make_exec = make_exec,
    make_inner_exec = make_inner_exec,
}
