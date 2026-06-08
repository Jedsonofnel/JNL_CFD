-- jnl/demo_nabla.lua
local nb      = require("jnl.fvm.nabla")
local Alg     = require("jnl.fvm.new_algorithm")
local rules   = require("jnl.fvm.rules")

local reg     = nb.new_registry("Incompressible NS + k-omega")
local rho     = reg:const("rho", 1.0)
local mu      = reg:const("mu", 1e-3)
local alpha_p = reg:const("alpha_p", 0.3)
local nu      = reg:scalar("nu"):defined_as(mu / rho)
local k       = reg:scalar("k"):initial(1e-4):clip(0, math.huge)
local omega   = reg:scalar("omega"):initial(1.0):clip(1e-10, math.huge)
local nut     = reg:scalar("nut"):defined_as(k / omega)
local nu_eff  = reg:scalar("nu_eff"):defined_as(nu + nut)
local U       = reg:vector("U")
local p       = reg:scalar("p")
local p_prime = reg:scalar("p_prime")
local divU    = reg:scalar("divU"):defined_as(nb.div(U))

U:governed_by(
	(nb.ddt(U) + nb.div(nb.outer(U, U))):equals(
		nb.laplacian(nu_eff, U) - nb.grad(p)))

p_prime:governed_by(
	nb.laplacian(p_prime):equals(nb.div(U)))

U:correction(U - nb.grad(p_prime))

p:correction(p + alpha_p * p_prime)

k:governed_by(
	(nb.ddt(k) + nb.div(U * k)):equals(nb.laplacian(nu_eff, k)))

omega:governed_by(
	(nb.ddt(omega) + nb.div(U * omega)):equals(nb.laplacian(nu_eff, omega)))

reg:validate()

local tol = 1e-6
local n   = 50

local alg = Alg.new("SIMPLE k-omega")
alg:loop(function(a)
	a:solve(U):tag("momentum")
	a:evaluate(divU)
	a:zero(p_prime)
	a:solve(p_prime):tag("pressure_correction")
	a:correct(U)
	a:correct(p)
	a:solve(k):tag("turb_k")
	a:solve(omega):tag("turb_omega")
end, 1000)

alg:converge(U, rules.residual_below(tol, n))
alg:converge(p_prime, rules.residual_below(tol, n))
alg:converge(k, rules.residual_below(tol, n))
alg:converge(omega, rules.residual_below(tol, n))
alg:guard(U, rules.field_is_nan())
alg:guard(p_prime, rules.field_is_nan())
alg:guard(k, rules.field_is_nan())
alg:guard(omega, rules.field_is_nan())
alg:watch(U, "residual")
alg:watch(p_prime, "residual")
alg:watch(k, "residual")
alg:watch(omega, "residual")
alg:watch(divU, "field_norm")

print(tostring(reg))
print()
print(reg:listing())
print()
print(reg:dep_listing())
print()
print(tostring(alg))
print()

alg:compile(reg)

print(tostring(alg))
print()
alg:print()
