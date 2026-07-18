-- jnl/fvm/plan.lua - rich plan objects for physics compilation target
-- <jed@nelson.ac> // 2026-07-17

--
-- Constructors
--

local Plan = {}
Plan.__index = Plan

local function new_linear_plan(...)
    local steps = { ... }

    return setmetatable({
        kind = "linear",
        steps = steps,
    }, Plan)
end

local function new_solve_plan(field)
    assert(field.defined, "field defined not checked earlier")

    if field.solve then
        return setmetatable({
            kind = "solve",
            field = field,
        }, Plan)
    end

    if field.eval then
        error("field.eval not implemented yet")
    end

    error("field.solve or field.eval not set")
end

--
-- Lowering
--

local function lower_plan(plan)
    return {}
end

function Plan:lower()
    return lower_plan(self)
end

--
-- Printing
--

local function linear_str(steps)
    local step_strs = {}
    for _, step in ipairs(steps) do
        step_strs[#step_strs + 1] = "  " .. step:__tostring()
    end

    local step_str = table.concat(step_strs, "\n  ")
    return "LINEAR:\n" .. step_str
end

local function plan_str(plan)
    local k = plan.kind

    if k == "linear" then
        return linear_str(plan.steps)
    elseif k == "solve" then
        return string.format("SOLVE %s", plan.field.name)
    else
        return "<unknown plan>"
    end
end

function Plan:__tostring()
    return plan_str(self)
end

return {
    linear = new_linear_plan,
    solve = new_solve_plan,
    lower = lower_plan,
}
