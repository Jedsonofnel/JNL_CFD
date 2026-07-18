-- demo_laplace.lua - Simple Laplacian solve
-- <jed@nelson.ac> // 2026-07-14

local cart = require("jnl.mesh2d.cartmesh2d")
local FVM = require("jnl.fvm")
local BC = FVM.BC

local ui = require("jnl.ui")
local repl = require("jnl.repl")

local mesh = cart.build(1, 1, 20, 20)
assert(mesh)

local physics = FVM.physics.new("laplacian")
local phi = physics:scalar("phi")
phi:governed_by(-FVM.laplacian(), 0)

local bcs = BC.new_set()
    :scalar("phi")
    :on(cart.SOUTH, BC.nograd())
    :on(cart.NORTH, BC.nograd())
    :on(cart.EAST, BC.dirichlet(1))
    :on(cart.WEST, BC.dirichlet(0))
    :build()

local function run()
    local case = FVM.case.new(physics, mesh, bcs)
    print(case.plan)

    error("not implemented the rest")
    case:run()

    ui.display_mesh(mesh)
    ui.set_field("phi", case:field("phi"))
    ui.view_field("phi")
end

local r = repl.new()
r:register("run", run, "Solve laplacian")

-- print("Laplacian demo.  (run) to solve.")
-- return r:run()

run()
