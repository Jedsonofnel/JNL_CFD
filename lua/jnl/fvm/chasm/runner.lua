-- jnl/fvm/chasm/runner.lua - CHASM runner
-- <jed@nelson.ac> // 2026-07-18

local Runner = {}
Runner.__index = Runner

local function new_runner()
    return setmetatable({}, Runner)
end

return {
    new = new_runner,
}
