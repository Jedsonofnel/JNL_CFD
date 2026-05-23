-- conv_diff_1d.lua - steady 1D convection-diffusion
-- <jed@nelson.ac> // 2026-05-22

local mesh2d = require("jnl.mesh2d")
local P      = mesh2d.smesh.PATCH
local FVM    = require("jnl.fvm")
local FVMe   = FVM.Expr
local Op     = FVM.Op
local BC     = require("jnl.fvm.bc")
local Reg    = require("jnl.core.registry")
local Alg    = require("jnl.core.algorithm")

local Sage   = require("jnl.sage")
local rules  = require("jnl.fvm.rules")

local L      = 1.0
local N      = 100
local rho    = 1.0
local u      = 1.0
local gamma  = 0.1
local Pe     = rho * u * L / gamma
print(string.format("Peclet number: %.2f", Pe))

local mesh = mesh2d.new_smesh(L, 1.0, N, 1)

--
-- Physics setup
--

local reg = Reg.new()

reg:constant("k", gamma)
reg:constant("rho", rho)

reg:uniform("Ux", u)
reg:uniform("Uy", u)
reg:vector("U", { "Ux", "Uy" })

reg:field("T", {
	eq = FVM.eq(
		Op.div("rho", FVMe.face_normal("U"), "T", { scheme = "SUPERBEE" }),
		Op.lap("k", "T")),
})

local alg = Alg.new()
alg:loop(function(a)
	a:solve("T")
end, { max_iters = 200 })

alg:add_ruleset(rules.stopping({
	converged = rules.all_fields({
		T = rules.any_of(
			rules.field_change_below(1e-6, 3),
			rules.field_stagnant(1e-6, 10)
		),
	}),
	diverged = rules.any_field({
		T = rules.field_above(1e15),
	}),
}))

local case = require("jnl.fvm.case").new(reg, alg, mesh, {
	T = {
		BC.dirichlet(P.LEFT, 0.0),
		BC.dirichlet(P.RIGHT, 1.0),
		BC.wall(P.TOP),
		BC.wall(P.BOTTOM),
	},
})

--
-- Solve (inline orchestrator)
--

case:allocate()
local runner = case:make_runner()
local sage   = Sage.new()

for _, rs in ipairs(alg.rulesets) do
	sage:add_ruleset(rs)
end

runner.on_solve = function(field, residual, iters, iter)
	sage:assert({
		kind = "residual",
		field = field,
		value = residual,
		iters = iters,
		iter = iter
	})
end

runner.on_monitor = function(field, value, iter, depth, norm)
	sage:assert({
		kind       = "field_norm",
		field      = field,
		value      = value,
		iter       = iter,
		loop_depth = depth,
		norm       = norm,
	})
end

-- print every 10 iterations rule
sage:add_rule("print_progress",
	function(f) return f.kind == "field_norm" and f.iter % 10 == 0 end,
	function(_, f)
		print(string.format("iter %4d  |%s|  norm = %.3e", f.iter, f.field, f.value))
	end
)

sage:add_rule("print_converged",
	function(f) return f.kind == "converged" end,
	function(_, f)
		print(string.format("converged: iter=%d loop_depth=%d", f.iter, f.loop_depth or 1))
	end
)

-- drive the loop manually for now
local stopped
repeat
	local ongoing = runner:run_step()

	if not ongoing then
		if runner:is_finished() then
			stopped = true
		else
			sage:assert({ kind = "iter_end", iter = runner._iter, loop_depth = 1 })
			for _, action in ipairs(sage:pop_actions()) do
				if action.kind == "stop" then stopped = true end
			end
			if not stopped then
				runner._iter = runner._iter + 1
				runner:reset()
			end
		end
	end
until stopped

--
-- Analytical solution
--

local function analytical(x)
	if math.abs(Pe) < 1e-12 then return x / L end
	return (math.exp(Pe * x / L) - 1.0) / (math.exp(Pe) - 1.0)
end

--
-- Output
--

local gp = require("jnl.gp")
local T  = case._field_map["T"]


local num_xs, num_ys = {}, {}
for i = 1, mesh:n_cells() do
	local x   = mesh:cell_centre(i)
	num_xs[i] = x
	num_ys[i] = T[i]
end

local ana_xs, ana_ys = gp.sample(analytical, 0, L)

gp.figure({
	title  = string.format("1D Conv-Diff  Pe = %.1f", Pe),
	xlabel = "x",
	ylabel = "T",
	grid   = true,
})
	:add(num_xs, num_ys, { title = "Numerical (SUPERBEE)", style = "points", pt = 7, color = "#0077bb" })
	:add(ana_xs, ana_ys, { title = "Analytical", style = "lines", lw = 2, color = "#ee3333" })
	:show()
