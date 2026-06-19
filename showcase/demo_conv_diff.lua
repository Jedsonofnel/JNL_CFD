-- showcase/demo_conv_diff.lua

local Physics = require("jnl.fvm.physics")
local nb = require("jnl.nabla")

local P = Physics.new("conv-diff")

local nu = P:const("nu", 1e-3)
local rho = P:const("rho", 1)
local U = P:cvec("U", 1, 0)
local T = P:scalar("T")

T:governed_by(
	nb.div(rho * U * T)
	:equals(nb.laplacian(nu * T))
)

P:compile()

print("demo conv-diff")
print(P)
