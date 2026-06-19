-- jnl/fvm/physics/plan.lua - plan objects for structured compilation
-- <jed@nelson.ac> // 2026-06-16

local M = {}

--
-- Plan object: constructors
--

local Plan = {}
Plan.__index = Plan

function M.new_solve(field, eq)
	return setmetatable({
		kind = "solve",
		field = field,
		eq = eq,
	}, Plan)
end

function M.new_correct(field, reg)
	return setmetatable({
		kind = "correct",
		field = field,
	}, Plan)
end

local function is_plan(p)
	return getmetatable(p) == Plan
end

--
-- Root Plan
--

local RootPlan = {}
RootPlan.__index = RootPlan

function M.new_root()
	return setmetatable({
		kind = "root",
		children = {},
	}, RootPlan)
end

function RootPlan:push(plan)
	if not is_plan(plan) then
		error("push: expected plan")
	end
	self.children[#self.children + 1] = plan
	return self
end

--
-- Inner Plan
--

local InnerPlan = {}
InnerPlan.__index = InnerPlan

function M.new_inner()
	return setmetatable({
		kind = "inner",
		children = {},
	}, InnerPlan)
end

return M
