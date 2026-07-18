-- jnl/fvm/chasm/init.lua - Conjugate Heat ASM
-- <jed@nelson.ac> // 2026-07-18

-- deps
local B = require("jnl.fvm.chasm.block")
local Var = require("jnl.fvm.chasm.var")

-- Instance of CHASM code

---@class CHASM
---@field name string
---@field partitions table[]
---@field vars CHASMvar[]
---@field blocks CHASMblock[]
local CHASM = {}
CHASM.__index = CHASM

---@class CHASMinstr
---@field build fun(...): table
---@field str fun(inst, cfg): string
---@field dispatch fun(case, exec, inst)

---@alias CHASMisa table<string, CHASMinstr>

---@class CHASMdialect
---@field ISA CHASMisa

local function new_chasm_instance(name, dialect)
    assert(dialect.ISA, "dialect must contain an instruction set")

    assert(dialect.lengths, "dialect must declare register lengths")
    assert(dialect.default_length, "dialect must declare a default length")
    assert(
        dialect.lengths[dialect.default_length],
        "dialect default_length must be a declared length kind"
    )

    assert(dialect.on_bind, "dialect must have on_bind function")

    -- TODO merge ISA with default chasm ISA (fill, copy, arithmetic etc)

    return setmetatable({
        name = name,
        partitions = {},
        vars = {},
        blocks = {},
        dialect = dialect,
    }, CHASM)
end

function CHASM:block(name, iters, cb)
    local block = B.new(self, name, iters)
    cb(block)
    self.blocks[#self.blocks + 1] = block
    return self
end

function CHASM:loop(name, iters, cb)
    return self:block(name, iters, cb)
end

function CHASM:once(name, cb)
    return self:block(name, 1, cb)
end

--
-- Var declaration
--

---@param name string
---@return CHASMvar
function CHASM:scalar(name)
    local var = Var.scalar(name)
    if self.vars[name] then
        error(string.format("CHASM:scalar: name '%s' already declared", name))
    end
    var.partition = "default"
    self.vars[name] = var
    return var
end

---@param var string|CHASMvar
---@return CHASMvar
function CHASM:get_field(var)
    var = Var.from(var)

    local found = self.vars[var.name]
    if not found then
        error(string.format("var '%s' not declared", var.name), 3)
    end
    return found
end

--
-- Pretty printing (as valid Lua code)
--

local function asm_manifest_str(asm)
    local scalars = {}

    for name, var in pairs(asm.vars) do
        if var.rank == 0 then
            scalars[#scalars + 1] =
                string.format('local %s = asm:scalar("%s")', name, name)
        end
    end

    return table.concat(scalars, "\n") .. "\n"
end

local function asm_str(asm)
    local manifest_str = asm_manifest_str(asm)

    local block_strs = {}
    for _, block in ipairs(asm.blocks) do
        block_strs[#block_strs + 1] = tostring(block)
    end

    local block_str = table.concat(block_strs, "\n\n")

    return manifest_str .. "\n" .. block_str
end

function CHASM:__tostring()
    return asm_str(self)
end

return {
    new = new_chasm_instance,
}
