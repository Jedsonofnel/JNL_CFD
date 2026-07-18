-- jnl/fvm/case.lua
-- <jed@nelson.ac> // 2026-06-10

---@class FVCase
---@field plan table
local Case = {}
Case.__index = Case

-- consider moving to bc.lua?
---@param mesh Mesh2D
local function validate_bcs(fields, mesh, bcs)
    local errors = {}
    local warnings = {}

    -- TODO check that no BCs defined for field that doesn't exist (warning)

    for _, field in ipairs(fields) do
        if not field.solve then
            goto continue
        end

        -- if bcs don't exist for this field then error
        -- if bcs exist and some patches in BC don't match with mesh then error
        -- if bcs exist but incomplete then default to neumann 0 and warn

        ::continue::
    end

    if #errors > 0 then
        error("BC errors found: TODO make this more informative")
    end

    return warnings
end

--- Create a new simulation case
---@param physics FVPhysics
---@param mesh Mesh2D
---@param bcs BCSet
---@return FVCase
local function new_case(physics, mesh, bcs)
    local plan = physics:compile()

    local warnings = validate_bcs(physics.fields, mesh, bcs)

    return setmetatable({
        physics = physics,
        mesh = mesh,
        bcs = bcs,
        plan = plan,
    }, Case)
end

--
-- Running
--

function Case:run()
    -- TODO:
    -- * compile physics into plan and plan into instructions
    print("running case")
end

return {
    new = new_case,
}
