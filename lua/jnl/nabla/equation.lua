-- jnl/nabla/equation.lua - equation object for Nabla library

local Node = require("jnl.nabla.node")
--
-- Equation: storage of nodes in lhs/rhs
--

local Equation = {}
Equation.__index = Equation

local function new_equation(lhs, rhs)
	lhs = Node.from(lhs)
	rhs = Node.from(rhs)

	return setmetatable({
		lhs = lhs,
		rhs = rhs,
	}, Equation)
end

function Equation.new(lhs, rhs)
	return new_equation(lhs, rhs)
end

function Equation:__tostring()
	return string.format("%s = %s", self.lhs, self.rhs)
end

function Equation:simplify()
	return new_equation(self.lhs:simplify(), self.rhs:simplify())
end

function Equation:residual()
	return self.lhs - self.rhs
end

return Equation
