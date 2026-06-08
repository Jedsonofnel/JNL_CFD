-- jnl/nabla/equation.lua - equation object for Nabla library

local Node = require("jnl.nabla.node")
--
-- Equation: storage of nodes in lhs/rhs
--

---Symbolic equation pairing a left-hand side and right-hand side Node.
---Constructed via Node:equals(rhs) or Equation.new(lhs, rhs).
---@class Equation
---@field lhs Node  Left-hand side expression.
---@field rhs Node  Right-hand side expression.
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

---Construct a new equation asserting lhs = rhs.
---Both sides are coerced to Node via Node.from.
---@param lhs Node|number
---@param rhs Node|number
---@return Equation
function Equation.new(lhs, rhs)
	return new_equation(lhs, rhs)
end

---Render the equation as "lhs = rhs".
---@return string
function Equation:__tostring()
	return string.format("%s = %s", self.lhs, self.rhs)
end

---Return a new equation with both sides independently simplified.
---@return Equation
function Equation:simplify()
	return new_equation(self.lhs:simplify(), self.rhs:simplify())
end

---Return the residual node lhs - rhs; zero at a solution.
---@return Node
function Equation:residual()
	return self.lhs - self.rhs
end

return Equation
