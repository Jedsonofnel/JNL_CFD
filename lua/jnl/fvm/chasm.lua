-- jnl/fvm/chasm.lua - Conjugate Heat ASM
-- <jed@nelson.ac> // 2026-07-17

-- deps
local V = require("jnl.core.validation")

-- Instance of CHASM code

---@class CHASM
---@field name string
---@field vars table[]
---@field blocks CHASMblock[]
local CHASM = {}
CHASM.__index = CHASM

local function new_chasm_instance(name)
    return setmetatable({
        name = name,
        vars = {},
        blocks = {},
    }, CHASM)
end

--
-- CHASM variable declaration
--

---@class CHASMvar
---@field name string
---@field rank integer
---@field has_sys boolean
local Var = {}
Var.__index = Var

function Var:sys()
    self.has_sys = true
    return self
end

function Var:residual_lt(v)
    return { kind = "lt", src = "residual", key = self.name, val = v }
end

function Var:residual_gt(v)
    return { kind = "gt", src = "residual", key = self.name, val = v }
end

-- TODO add norm and delta predicates too

---@param name string
---@return CHASMvar
function CHASM:scalar(name)
    V.identifier(name, "CHASM:scalar(name)")

    if self.vars[name] then
        error(string.format("CHASM:scalar: name '%s' already declared", name))
    end

    ---@type CHASMvar
    local var = setmetatable({ name = name, rank = 0, has_sys = false }, Var)
    self.vars[name] = var
    return var
end

---@param var string|CHASMvar
---@return CHASMvar
function CHASM:get_field(var)
    if type(var) == "string" and self.vars[var] then
        return self.vars[var]
    elseif
        type(var) == "table"
        and type(var.name) == "string"
        and self.vars[var.name]
    then
        return var
    end

    error("expected a CHASM variable", 3)
end

--
-- CHASM Blocks (main unit of code organisation)
--

---@class CHASMblock
---@field asm CHASM
---@field name string
---@field iters integer
---@field depth integer
---@field instructions table[]|CHASMblock[]
---@field converge table[]
local Block = {}
Block.__index = Block

local function new_chasm_block(asm, name, iters, depth)
    depth = depth or 1

    local block = setmetatable({
        asm = asm,
        name = name,
        iters = iters,
        depth = depth,
        instructions = {},
        converge = {},
    }, Block)

    return block
end

function CHASM:block(name, iters, cb)
    local block = new_chasm_block(self, name, iters)
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

function Block:add_instr(instr)
    self.instructions[#self.instructions + 1] = instr
end

function Block:get_field(var)
    return self.asm:get_field(var)
end

-- Builder predicate addition
function Block:until_all(...)
    local args = { ... }
    if #args == 0 then
        error("Builder:until_all expects at least one predicate")
    end

    -- TODO some sort of predicate type checking/validation

    self.converge[#self.converge + 1] = { kind = "all", preds = args }
end

function Block:until_any(...)
    local args = { ... }
    if #args == 0 then
        error("Builder:until_any expects at least one predicate")
    end

    -- TODO predicate type/validation checking
    self.converge[#self.converge + 1] = { kind = "any", preds = args }
end

-- Create nested block
function Block:block(name, max_n, cb)
    local inner = new_chasm_block(self.asm, name, max_n, self.depth + 1)
    cb(inner)
    self.instructions[#self.instructions + 1] = inner
    return self
end

--
-- CHASM FVM Instructions
--

function Block:sys_reset(field)
    self:add_instr({
        op = "sys_reset",
        field = field,
    })
    return self
end

function Block:laplacian_k(field, gamma, expr)
    gamma = gamma or 1
    self:add_instr({
        op = "laplacian_k",
        field = field,
        coeff = gamma,
        node = expr,
    })
    return self
end

function Block:bc_close(field)
    self:add_instr({
        op = "bc_close",
        field = field,
    })
end

--
-- Krylov iteration
--

function Block:krylov(field, config)
    field = self:get_field(field)
    -- TODO config validation

    self:block(
        self.name .. ":krylov:" .. field.name,
        config.max_iters,
        function(b)
            b:add_instr({ op = "krylov_iter", field = field })
            b:until_all(field:residual_lt(config.tol))
        end
    )

    return self
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

---@param block CHASMblock
local function asm_block_str(block, indent_level)
    indent_level = indent_level or 0

    local outer_builder_name = "b"
    for _ = 1, block.depth - 2 do
        outer_builder_name = "i" .. outer_builder_name
    end
    local inner_builder_name = block.depth == 1 and "b"
        or "i" .. outer_builder_name
    if block.depth == 1 then
        outer_builder_name = "asm"
    end

    local lines = {}

    local indent_prefix = ""
    for _ = 1, indent_level do
        indent_prefix = indent_prefix .. "  "
    end

    -- TODO add once and krylov checking
    lines[#lines + 1] = string.format(
        '%s:block("%s", %d, function(%s)',
        outer_builder_name,
        block.name,
        block.iters,
        inner_builder_name
    )

    -- use instr.__tostring here
    for _, instr in ipairs(block.instructions) do
        if getmetatable(instr) == Block then
            lines[#lines + 1] =
                string.format("\n  %s", instr:__tostring(indent_level + 1))
        else
            lines[#lines + 1] = string.format(
                "  %s%s:%s",
                indent_prefix,
                inner_builder_name,
                instr
            )
        end
    end

    lines[#lines + 1] = indent_prefix .. "end)"

    return table.concat(lines, "\n")
end

function Block:__tostring(indent_level)
    indent_level = indent_level or 0
    return asm_block_str(self, indent_level)
end

local function asm_str(asm)
    local manifest_str = asm_manifest_str(asm)

    local block_strs = {}
    for _, block in ipairs(asm.blocks) do
        block_strs[#block_strs + 1] = asm_block_str(block)
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
