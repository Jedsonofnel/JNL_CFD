-- jnl/fvm/sim.lua - FVM wrapped sim
-- <jed@nelson.ac> // 2026-05-23

local CoreSim = require("jnl.core.sim")

local Sim = {}
Sim.__index = Sim

--
-- Constructor
--

function Sim.new(runner, alg, opts)
	opts = opts or {}

	-- wire FVM-specific callbacks onto runner
	local sage_getter -- set after core construction

	runner.on_solve = function(field, residual, n_iters, iter, depth)
		sage_getter():assert({
			kind = "residual",
			field = field,
			value = residual,
			iters = n_iters,
			iter = iter,
			loop_depth = depth
		})
	end

	runner.on_monitor = function(field, value, iter, depth, norm)
		sage_getter():assert({
			kind = "field_norm",
			field = field,
			value = value,
			iter = iter,
			loop_depth = depth,
			norm = norm
		})
	end

	local orch = CoreSim.new(runner, alg, { sage = opts.sage })
	sage_getter = function() return orch._sage end

	return setmetatable({ _core = orch }, Sim)
end

--
-- Methods
--

-- delegate to core
function Sim:run() return self._core:run() end

function Sim:step() return self._core:step() end

function Sim:is_finished() return self._core:is_finished() end

function Sim:sage() return self._core:sage() end

--
-- Rules
--

function Sim:add_rule(name, match_fn, fire_fn)
	self._core:sage():add_rule(name, match_fn, fire_fn)
end

function Sim:add_rules(...)
	for _, r in ipairs({ ... }) do
		self._core:sage():add_rule(r.name, r.match, r.fire)
	end
end

return Sim
