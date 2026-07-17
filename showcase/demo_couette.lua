-- demo_couette.lua - Plane Couette flow
-- <jed@nelson.ac> // 2026-06-13

local preset = require("jnl.fvm.preset")
local cart = require("jnl.mesh2d.cartesian")
local bc = require("jnl.fvm.bc")
local E = require("jnl.mesh2d.edges")
local Case = require("jnl.fvm.case")
local ui = require("jnl.ui")
local repl = require("jnl.repl")

local P = E.PATCH

local m = cart.build(0.25, 1.0, 4, 32)
assert(m)

local bcs = bc.new_set()
	:vector("U")
	:on(P.SOUTH, bc.no_slip())
	:on(P.NORTH, bc.moving_wall(1, 0))
	:on(P.EAST, bc.outlet())
	:on(P.WEST, bc.outlet())
	:scalar("p")
	:all(bc.nograd())
	:scalar("p_prime")
	:all(bc.nograd())
	:build()

local function run()
	local reg = preset.reg.stokes()
	local alg = preset.alg.simple()

	alg:set_cfg("p_prime", "solver", "cg_dic")
	local c = Case.new(reg, alg, m, bcs)

	print(c.compiled.alg:instruction_listing())

	c:run()

	ui.display_mesh(m)
	ui.set_field("U_x", c:real_field("U_x"))
	ui.set_field("U_y", c:real_field("U_y"))
	ui.set_vector("U", "U_x", "U_y")
	ui.view_field("U")

	return c
end

local r = repl.new()
r:register("run", run, "Solve Couette flow.")
print("Couette demo.  (run) to solve.")
return r:run()
