-- jnl/fvm/chasm/block.lua - CHASM blocks, the main unit of code org
-- <jed@nelson.ac> // 2026-07-18

---@class CHASMblock
---@field prog CHASMprogram
---@field name string
---@field iters integer
---@field depth integer
---@field instructions table[]|CHASMblock[]
---@field converge table[]
local Block = {}

Block.__index = function(self, key)
    local v = rawget(self, key)
    if v ~= nil then
        return v
    end

    local prog = rawget(self, "prog")
    if prog and prog.ISA then
        local isa_entry = prog.ISA[key]
        if isa_entry then
            return function(block, ...)
                local instr = isa_entry.build(block, ...)
                instr.op = key
                block:add_instr(instr)
                return block
            end
        end
    end

    return rawget(Block, key)
end

local function new_chasm_block(prog, name, iters, depth)
    assert(prog, "new_chasm_block: prog is nil, required")
    depth = depth or 1

    ---@type CHASMblock
    local block = setmetatable({
        prog = prog,
        name = name,
        iters = iters,
        depth = depth,
        instructions = {},
        converge = {},
    }, Block)

    return block
end

function Block:add_instr(instr)
    self.instructions[#self.instructions + 1] = instr
end

function Block:get_var(var)
    return self.prog:get_var(var)
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
    local inner = new_chasm_block(self.prog, name, max_n, self.depth + 1)
    cb(inner)
    self.instructions[#self.instructions + 1] = inner
    return self
end

--
-- Krylov iteration
--

function Block:krylov(field, config)
    field = self:get_var(field)
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
-- Pretty printing
--

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
                block.prog.ISA[instr.op].str(instr)
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

return {
    new = new_chasm_block,
}
