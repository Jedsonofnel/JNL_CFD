local Physics = require("jnl.fvm.physics")
local nb = require("jnl.nabla")

local M = {}

function M.conv_diff()
	local P = Physics.new("conv-diff")

	local nu = P:const("nu", 1e-3)
	local rho = P:const("rho", 1)
	local U = P:cvec("U", 1, 0)
	local T = P:scalar("T")

	T:governed_by(
		nb.div(rho * U * T)
		:equals(nb.laplacian(nu * T))
	)

	return P
end

function M.ns()
	local P = Physics.new("navier-stokes")

	local nu = P:const("nu", 1e-3)
	local U = P:vector("U")
	local p = P:scalar("p")
	local p_prime = P:scalar("p_prime")

	U:governed_by(
		nb.div(U:mwi(p) * U):equals(
			nb.laplacian(nu * U) - nb.grad(p))
	)

	local inv_d = P:scalar("inv_d")
		:defined_as(
			nb.cV() * 2 / (U:diag().x + U:diag().y)
		)

	p_prime:governed_by(
		nb.laplacian(inv_d * p_prime)
		:equals(-nb.div(nb.mwi(U)))
	)

	U:correction(-nb.cV() * nb.grad(p_prime) / U:diag())
	p:correction(p_prime)

	P:algorithm(function(b)
		b:solve(U)
		b:zero(p_prime)
		b:solve(p_prime)
		b:correct(U)
		b:correct(p)
	end)

	return P
end

return M
