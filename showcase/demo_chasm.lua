-- showcase/demo_chasm.lua - CHASM demo for low-level FVM instructions
-- <jed@nelson.ac> // 2026-07-17

local cart = require("jnl.mesh2d.cartmesh2d")
local FVM = require("jnl.fvm")
local BC = FVM.BC
local ui = require("jnl.ui")
local repl = require("jnl.repl")

local mesh = cart.build(1, 1, 20, 20)
assert(mesh)

local asm = FVM.chasm.new("laplace")

local su = asm:const("su", 3)
local phi = asm:scalar("phi"):sys()

asm:main(function(b)
    b:sys_reset(phi)
    b:laplacian_k(phi)
    b:su_k(phi, su)
    b:bc_close(phi)
    b:krylov(phi, { max_iters = 1000, tol = 1e-6, solver = "bicgstab_dilu" })
end)

local bcs = BC.new_set()

bcs:scalar("phi")
    :on(cart.EAST, BC.dirichlet(0))
    :on(cart.WEST, BC.dirichlet(1))
    :rest(BC.nograd())

asm:bind(mesh, bcs)

local function run()
    local vm = asm:start()
    vm:run_all()

    ui.display_mesh(mesh)
    ui.set_field("phi", phi.vec)
    ui.view_field("phi")
end

local r = repl.new()
r:register("run", run, "execute CHASM program")

return r:run()
