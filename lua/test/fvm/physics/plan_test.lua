-- test/fvm/physics/plan_test.lua - Plan lowering testing

local h = require("test.harness")
local nb = require("jnl.nabla")
local plan = require("jnl.fvm.physics.plan")

--
-- Fixtures
--

local function make_laplacian_eq()
    local phi = nb.scalar("phi")
    local eq = nb.laplacian(phi):equals(0)

    return eq
end

local function make_poisson_eq()
    local phi = nb.scalar("phi")
    local mu = nb.const("mu", 5)
    local rho = nb.const("rho", 2)

    local eq = nb.laplacian(mu / rho * phi):equals(1)

    return eq
end

--
-- Tests
--

h.describe("solve plan for laplacian lowers to instructions", function()
    local eq = make_laplacian_eq()
    local solve_plan = plan.new_solve_plan(eq)

    -- should be EVAL_COEFF (mu/rho)
    -- then LAPLACIAN
    local instructions = plan.lower(solve_plan)

    h.it("eval coeff is done first", function()
        h.expect(instructions[1].kind == "eval_coeff")
    end)
end)
