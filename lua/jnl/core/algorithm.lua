-- algorithm.lua - storage for algorithmic steps for a solver
-- <jed@nelson.ac> // 2026-05-11

-- deps
local V = require("core.validation")

local A = {}
A.__index = A

function A.new()
	return setmetatable({ _final = {} }, A)
end

-- constructors

function A:linear(cb)
	self.op = "linear"
	local target = {}

	function target:solve(field)
		V.identifier(field, "alg:solve field")
		self[#self + 1] = { op = "solve", field = field }
		return self
	end

	function target:clip(field, lo, hi)
		V.identifier(field, "alg:clip field")
		V.typeof(lo, "number", "alg:clip lo")
		V.typeof(hi, "number", "alg:clip hi")
		self[#self + 1] = { op = "clip", field = field, lo = lo, hi = hi }
		return self
	end

	function target:hook(fn, name)
		V.typeof(fn, "function", "alg:hook fn")
		self[#self + 1] = { op = "hook", fn = fn, name = name or "<fn>" }
		return self
	end

	function target:inner(fn, config)
		V.typeof(fn, "function", "alg:inner fn")
		V.typeof(fn, "table", "alg:inner config")
		local inner_alg = A.new()
		inner_alg:loop(fn, config)
		self[#self + 1] = { op = "inner", inner = inner_alg }
		return self
	end

	cb(target)
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

--- Push step onto _final array for steps to be ran after the main solve loop.
function A:push_final(step)
	self._final[#self._final + 1] = step
end

--
-- Pretty printing
--

--- Returns a pretty string depicting the algorithm
function A:_pretty(heading, ending)
	local lines = {}
	lines[1] = heading or self.op == "loop" and ".LOOP:" or ".LINEAR:"

	for _, inst in ipairs(self) do
		if inst.op == "solve" then
			lines[#lines + 1] = "  SOLVE " .. inst.field
		elseif inst.op == "clip" then
			lines[#lines + 1] = string.format("  CLIP %s %g %g", inst.field, inst.lo, inst.hi)
		elseif inst.op == "hook" then
			lines[#lines + 1] = string.format("  HOOK %s", inst.name)
		elseif inst.op == "inner" then
			lines[#lines + 1] = inst.inner:pretty("\n>>INNER", "<<END\n")
		end
	end

	lines[#lines + 1] = ending or ".END"

	return table.concat(lines, "\n")
end

return A
