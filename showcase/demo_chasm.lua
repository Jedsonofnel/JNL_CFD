-- showcase/demo_chasm.lua - CHASM demo for low-level FVM instructions
-- <jed@nelson.ac> // 2026-07-17

local cart = require("jnl.mesh2d.cartmesh2d")
local CHASM = require("jnl.fvm.chasm")

local mesh = cart.build(1, 1, 20, 20)
assert(mesh)

local asm = CHASM.new("laplace")

local phi = asm:scalar("phi"):sys()

asm:once("procedure", function(b)
    b:sys_reset(phi)
    b:laplacian_k(phi)
    b:bc_close(phi)
    b:krylov(phi, { max_iters = 1000, tol = 1e-6 })
end)

print(asm)
