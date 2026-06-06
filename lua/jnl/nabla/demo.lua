-- jnl/nabla/init.lua usage section (or a standalone test)

local nb = require("jnl.nabla")
local reg = nb.new_registry("Incompressible NS — laminar 2D")
local Node = require("jnl.nabla.node")

-- constants
local rho = reg:const("rho", 1.0)
local mu = reg:const("mu", 1e-3)
local g = reg:cvec("g", 0, -9.81)
local beta = reg:const("beta", 3.4e-3)

-- diagnostic: algebraic, no solve
local nu = reg:scalar("nu"):defined_as(mu / rho)
local nu_eff = reg:scalar("nu_eff"):defined_as(nu)

-- primary prognostic fields
local U = reg:vector("U")
local p = reg:scalar("p")
local p_prime = reg:scalar("p_prime")

-- governing equations
U:governed_by(
	(nb.ddt(U) + nb.div(nb.outer(U, U)))
	:equals(nb.laplacian(nu_eff, U) - nb.grad(p))
)

p_prime:governed_by(
	nb.laplacian(p_prime):equals(nb.div(U))
)

-- corrections
U:correction(U - nb.grad(p_prime))
p:correction(p + p_prime)

-- temperature: passive scalar transport
local T = reg:scalar("T"):initial(293.0)
local T_ref = reg:const("T_ref", 293.0)

T:governed_by(
	(nb.ddt(T) + nb.div(U * T))
	:equals(nb.laplacian(nu_eff, T))
)

-- add Boussinesq buoyancy to U after the fact
U:add_rhs(beta * (T - T_ref) * g)

-- turbulent KE — with physical bounds
local k = reg:scalar("k"):initial(1e-4):clip(0, math.huge)
local omega = reg:scalar("omega"):initial(1.0):clip(1e-10, math.huge)
local nut = reg:scalar("nut"):defined_as(k / omega)

-- redefine nu_eff now that nut exists
nu_eff:defined_as(nu + nut)

k:governed_by(
	(nb.ddt(k) + nb.div(U * k))
	:equals(nb.laplacian(nu_eff, k))
)

omega:governed_by(
	(nb.ddt(omega) + nb.div(U * omega))
	:equals(nb.laplacian(nu_eff, omega))
)

reg:validate()

print(tostring(reg))
print()
print(reg:listing())
print()
print(reg:dep_listing())

local e = reg:entry("U")
if e.equation then
	local r = e.equation:residual()
	print("U residual: " .. tostring(r))
end

print()
print("Resolved scalar equations (ndims=2)")
print(string.rep("─", 44))

local nb_resolve = require("jnl.nabla.resolve")

reg:each(function(name, entry)
	if not entry.equation then return end

	local ok, result = pcall(nb_resolve.resolve_equation, entry.equation, 2)
	if not ok then
		print(string.format("  %-10s : [%s]", name, result))
		return
	end

	if #result == 1 then
		-- scalar equation: print on one line
		print(string.format("  %-10s : %s", name, tostring(result[1])))
	else
		-- vector equation: one line per component
		print(string.format("  %s", name))
		for i, eq in ipairs(result) do
			print(string.format("    (%s)  %s",
				Node.AXES[i], tostring(eq)))
		end
	end
end)
