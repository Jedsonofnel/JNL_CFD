-- showcase/demo_chasm.lua - CHASM demo for low-level FVM instructions
-- <jed@nelson.ac> // 2026-07-17

local cart = require("jnl.mesh2d.cartmesh2d")
local FVM = require("jnl.fvm")

local mesh = cart.build(1, 1, 20, 20)
assert(mesh)

local asm = FVM.chasm.new("laplace")

local phi = asm:scalar("phi"):sys()

asm:main(1, function(b)
    b:sys_reset(phi)
    b:laplacian_k(phi)
    b:bc_close(phi)
    b:krylov(phi, { max_iters = 1000, tol = 1e-6, solver = "bicgstab_dilu" })
end)

print(asm)

-- TODO work out VM API and how to get it to run?
asm:bind(mesh)
