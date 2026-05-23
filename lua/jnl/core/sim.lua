-- jnl/core/sim.lua - general orchestrator to run runners
-- <jed@nelson> // 2026-05-23

local Sim = {}
Sim.__index = Sim

function Sim.new(runner, alg, opts)
	opts = opts or {}
	local Sage = require("jnl.sage")
	local sage = opts.sage or Sage.new()

	for _, rs in ipairs(alg.rulesets) do
		sage:add_ruleset(rs)
	end

	return setmetatable({
		_runner  = runner,
		_sage    = sage,
		_stopped = false,
		_on_iter = opts.on_iter, -- optional: called each sweep end
	}, Sim)
end

-- returns true while still running
function Sim:step()
	if self._stopped then return false end

	local ongoing = self._runner:run_step()

	if not ongoing then
		if self._runner:is_finished() then
			self._stopped = true
			return false
		end

		-- sweep complete
		self._sage:assert({
			kind       = "iter_end",
			iter       = self._runner._iter,
			loop_depth = 1,
		})

		if self._on_iter then
			self._on_iter(self._runner._iter, self._runner)
		end

		for _, action in ipairs(self._sage:pop_actions()) do
			if action.kind == "stop" then
				self._stopped = true
			end
			-- unknown actions ignored here — domain layer handles them
		end

		if not self._stopped then
			self._runner._iter = self._runner._iter + 1
			self._runner:reset()
		end
	end

	return not self._stopped
end

function Sim:run()
	while self:step() do end
end

function Sim:is_finished()
	return self._stopped
end

return Sim
