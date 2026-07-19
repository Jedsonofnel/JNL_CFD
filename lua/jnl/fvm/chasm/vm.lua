-- jnl/fvm/chasm/vm.lua - CHASM virtual machine and execution ctx
-- <jed@nelson.ac> // 2026-07-19

---@class CHASMvm
---@field prog CHASMprogram
local VM = {}
VM.__index = {}

---@param prog CHASMprogram
---@return CHASMvm
local function new_vm(prog)
    return setmetatable({
        prog = prog,
    }, VM)
end

function VM:start()
    self.prog:allocate()

    -- TODO start a coroutine
end

function VM:step()
    return { exec = "context" }
end

return {
    new = new_vm,
}
