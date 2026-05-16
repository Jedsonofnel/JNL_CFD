-- algorithm.lua - storage for algorithmic steps for a solver
-- <jed@nelson.ac> // 2026-05-11

-- deps
local V = require("core.validation")

local A = {}
A.__index = A

function A.new()
	return setmetatable({}, A)
end

-- constructors

function A:linear(cb)
	self.op = "linear"

	local steps = {}
	local target = {}

	function target:solve(field)
		V.identifier(field, "solve field")
		steps[#steps + 1] = { op = "solve", field = field }
		return self
	end

	function target:clip(field, lo, hi)
		V.identifier(field, "clip field")
		V.typeof(lo, "number", "clip lo")
		V.typeof(hi, "number", "clip hi")
		steps[#steps + 1] = { op = "clip", field = field, lo = lo, hi = hi }
		return self
	end

	function target:hook(fn)
		V.typeof(fn, "function", "hook fn")
		steps[#steps + 1] = { op = "hook", fn = fn }
		return self
	end

	function target:inner(fn, config)
		V.typeof(fn, "function", "inner fn")
		V.typeof(fn, "table", "inner config")
		steps[#steps + 1] = { op = "inner", fn = fn, config = config }
		return self
	end

	cb(target)

	self.steps = steps
end

function A:loop(cb, config)
	A:linear(cb)
	self.op = "loop"
	self.max_iters = config.max_iters or 1000
	self.go_until = config.go_until
end

-- helpers

function A:push(step)
	self[#self + 1] = step
end

function A:prepend(step)
	table.insert(self, 1, step)
end

function A:insert_before(name, step)
	for i, s in ipairs(self) do
		if s.field == name then
			table.insert(self, i, step)
			return
		end
	end
	error("algorithm: no step found for field '" .. name .. "'")
end

return A
