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

	runner.on_monitor = function(field, value, iter, depth, kind)
		sage_getter():assert({
			kind = kind,
			field = field,
			value = value,
			iter = iter,
			loop_depth = depth,
		})
	end

	local sim = CoreSim.new(runner, alg, { sage = opts.sage })
	sage_getter = function() return sim._sage end

	-- diagnostic object
	local diag = {
		field = function(name) return runner:_field(name) end,
		residual = function(name) return runner:last_residual(name) end,
		is_nan = function(name)
			local f = runner:_field(name)
			return f:norm_linf() ~= f:norm_linf()
		end,
		max = function(name) return runner:_field(name):norm_linf() end,
		iter = function() return runner:iteration() end,
		sys_diag = function(name)
			local sys = runner:_sys(name)
			if not sys then return nil end
			return {
				diagonal_dominance     = sys:diagonal_dominance(),
				all_diagonals_positive = sys:all_diagonals_positive(),
				max_asymmetry          = sys:max_asymmetry(),
				residual_norm          = sys:residual_norm(runner:_field(name)),
			}
		end,
	}

	return setmetatable({ _core = sim, diag = diag }, Sim)
end

--
-- Methods
--

-- delegate to core
function Sim:run()
	self._core:run()

	local sage = self._core._sage
	local conclusion = sage:last_one({ kind = "diverging" })

	if conclusion then
		sage:derive({
			kind = "post_mortem",
			iter = conclusion.iter,
			diagnostics = self.diag,
		}, { conclusion.id })
	end
end

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

--
-- API
--

Sim._doc = "FVM simulation wrapper: wires runner callbacks into Sage and drives the solver loop."

Sim._doc_subsection =
	"Obtain via Case:make_sim() rather than constructing directly. Call :run() for a " ..
	"full solve, or :step() / :is_finished() for manual iteration. Post-mortem rules " ..
	"fire automatically on divergence. Access field data and matrix diagnostics through " ..
	"the diag object for custom rules and post-processing."

Sim._api = {
	new         = { args = "runner, alg, opts?", ret = "Sim", doc = "Wire FVM callbacks onto runner and construct core sim; prefer Case:make_sim()" },
	run         = { args = "", ret = "nil", doc = "Run until convergence or divergence; fires post-mortem rules on divergence" },
	step        = { args = "", ret = "nil", doc = "Advance one outer iteration" },
	is_finished = { args = "", ret = "bool", doc = "True if the solver has converged, diverged, or hit max_iters" },
	sage        = { args = "", ret = "Sage", doc = "Return the underlying Sage fact store for custom rule queries" },
	add_rule    = { args = "name, match_fn, fire_fn", ret = "nil", doc = "Register a custom Sage rule" },
	add_rules   = { args = "...rules", ret = "nil", doc = "Register multiple rules from { name, match, fire } tables" },
}

Sim._types = {
	Diag = {
		doc         = "Diagnostic accessor passed to post-mortem rule functions as f.diagnostics",
		constructor = "available as sim.diag after Sim.new()",
		kind        = "table",
		methods     = {
			field    = { args = "name:string", ret = "vec", doc = "Raw cell field vec for the named field" },
			residual = { args = "name:string", ret = "number", doc = "Last linear solver residual for the named field" },
			is_nan   = { args = "name:string", ret = "bool", doc = "True if field contains any NaN values" },
			max      = { args = "name:string", ret = "number", doc = "L-infinity norm of field (max absolute value)" },
			iter     = { args = "", ret = "int", doc = "Current outer iteration count" },
			sys_diag = { args = "name:string", ret = "table?", doc = "Matrix diagnostics: { diagonal_dominance, all_diagonals_positive, max_asymmetry, residual_norm } or nil if no system" },
		},
	},
}

return Sim
