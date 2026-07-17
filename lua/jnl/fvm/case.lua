-- jnl/fvm/case.lua
-- <jed@nelson.ac> // 2026-06-10

--
-- Case constructor
--

---@class FVCase
local Case = {}
Case.__index = Case

--- Create a new simulation case
---@param physics FVPhysics
---@param mesh Mesh2D
---@param bcs BCSet
---@return FVCase
local function new_case(physics, mesh, bcs)
    physics:validate()
    -- TODO:
    -- * get physics warnings and errors
    -- * check BCs are all hunky dory with the mesh + physics
    print("creating new case")

    return setmetatable({
        fields = physics.fields,
        mesh = mesh,
        bcs = bcs,
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
