-- jnl/fvm/physics.lua - physics specifier system for FVM
-- <jed@nelson.ac> // 2026-07-16

-- deps
local nb = require("jnl.nabla")
local terms = require("jnl.fvm.terms")
local P = require("jnl.fvm.plan")

local V = require("jnl.core.validation")

--
-- Physics object constructor
--

---@class FVPhysics
---@field label string
---@field fields RegistryField[]
---@field algorithm table
local Physics = {}
Physics.__index = Physics

local function new_physics(label)
    return setmetatable({
        label = label,
        fields = {},
        algorithm = {},
    }, Physics)
end

--
-- Field constructors
--

---@class RegistryField : Node
---@field governed_by fun(self: RegistryField, lhs: TermList|Term, rhs?: Node|number): RegistryField
---@field defined_as  fun(self: RegistryField, expr: Node): RegistryField
---@field initial     fun(self: RegistryField, v: number): RegistryField
---@field clip        fun(self: RegistryField, lo: number, hi?: number): RegistryField

--- Create a named scalar node
---@param name string
---@return RegistryField
function Physics:scalar(name)
    local node = nb.scalar(name) --[[@as RegistryField]]
    local entry = { name = name, node = node, defined = false }
    self.fields[name] = entry

    function node:governed_by(lhs, rhs)
        if getmetatable(lhs) == terms.TermList then
            entry.lhs = lhs
        elseif getmetatable(lhs) == terms.Term then
            entry.lhs = terms.new_termlist(lhs)
        else
            error(
                string.format(
                    "%s:governed_by: expected Term or TermList as lhs",
                    name
                )
            )
        end

        if rhs == nil or rhs == 0 then
            entry.rhs = nil
        else
            local source_node = nb.Node.from(rhs)
            if source_node.rank ~= 0 then
                error(
                    string.format(
                        "%s:governed_by: expected source (rank %d) to have same rank as %s (rank 0)",
                        source_node.rank,
                        name
                    )
                )
            end
            entry.rhs = source_node
        end

        entry.solve = true
        entry.defined = true
        return self
    end

    function node:initial(value)
        V.typeof(value, "number", name .. ":initial")
        entry.initial = value
        return self
    end

    return node
end

--
-- Validation
--

local function validate_fields(fields)
    local errors = {}
    local warnings = {}

    for _, field in pairs(fields) do
        if not field.defined then
            errors[#errors + 1] =
                string.format("field %s: undefined", field.name)
        end

        if not field.initial then
            warnings[#warnings + 1] = string.format(
                "field %s: no initial value given, defaulting to 0",
                field.name
            )
        end
    end

    return errors, warnings
end

function Physics:compile()
    local errors, warnings = validate_fields(self.fields)
    if #errors > 0 then
        error("Field errors found, TODO: make this more informative")
    end

    if #warnings > 0 then
        print("Warnings: TODO make this more informatinve")
    end

    local num_fields = 0
    local field_name
    for name, field in pairs(self.fields) do
        num_fields = num_fields + 1

        if num_fields > 1 then
            error(
                "more than one field declared in physics, not setup for that yet"
            )
        end
        field_name = name
    end

    local plan = P.linear(P.solve(self.fields[field_name]))

    return plan
end

return {
    new = new_physics,
}
