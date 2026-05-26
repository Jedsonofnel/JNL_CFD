-- lua/jnl/fvm/study.lua - FVM-specific REPL study helper
-- <jed@nelson.ac> // 2026-05-26

local base = require("jnl.repl.study")
local Case = require("jnl.fvm.case")
local ui = require("jnl.ui")
local E = require("jnl.core.expr")

local M = {}
local FvmStudy = {}
FvmStudy.__index = FvmStudy
setmetatable(FvmStudy, { __index = base.Study })

M._doc = "FVM-specific study helper with automatic case builders and inspectors"

M._doc_subsection = {
	"Use jnl.fvm.study when a script can expose mesh, registry, algorithm, and boundary-condition builders.",
	"Builders receive design variables first and run options second: fn(design, opts). Use design for sweep/optimisation variables, and defaults/options for ordinary run configuration.",
	"The helper registers standard REPL inspectors such as inspect-registry, inspect-deps, inspect-instructions, and run, while still allowing custom evaluate, output, plot, write, and optimisation functions.",
}

local function as_callable(name, fn)
	if type(fn) ~= "function" then
		error(name .. " must be a function")
	end

	return fn
end

function M.new(title)
	local self = base.new(title)
	return setmetatable(self, FvmStudy)
end

function FvmStudy:mesh(fn, opts)
	self.mesh_fn = as_callable("mesh", fn)
	self.mesh_opts = opts or {}
	return self
end

function FvmStudy:registry(fn, opts)
	self.registry_fn = as_callable("registry", fn)
	self.registry_opts = opts or {}
	return self
end

function FvmStudy:algorithm(fn, opts)
	self.algorithm_fn = as_callable("algorithm", fn)
	self.algorithm_opts = opts or {}
	return self
end

function FvmStudy:bcs(fn, opts)
	self.bcs_fn = as_callable("bcs", fn)
	self.bcs_opts = opts or {}
	return self
end

function FvmStudy:case(fn, opts)
	self.case_fn = as_callable("case", fn)
	self.case_opts = opts or {}
	return self
end

function FvmStudy:build_mesh(arg)
	if not self.mesh_fn then
		error("No mesh builder has been registered")
	end

	return self.mesh_fn(self:design_opts(arg), self:opts(arg))
end

function FvmStudy:build_registry(arg)
	if not self.registry_fn then
		error("No registry builder has been registered")
	end

	return self.registry_fn(self:design_opts(arg), self:opts(arg))
end

function FvmStudy:build_algorithm(arg)
	if not self.algorithm_fn then
		error("No algorithm builder has been registered")
	end

	return self.algorithm_fn(self:design_opts(arg), self:opts(arg))
end

function FvmStudy:build_bcs(arg)
	if not self.bcs_fn then
		return {}
	end

	return self.bcs_fn(self:design_opts(arg), self:opts(arg))
end

function FvmStudy:build_case(arg)
	local x = self:design_opts(arg)

	if self.case_fn then
		return self.case_fn(x, self:opts())
	end

	local mesh = self:build_mesh(x)
	local reg = self:build_registry(x)
	local alg = self:build_algorithm(x)
	local bcs = self:build_bcs(x)

	return Case.new(reg, alg, mesh, bcs)
end

function FvmStudy:build_case_with(design_overrides, option_overrides)
	local x = self:design_opts(design_overrides)
	local o = self:opts(option_overrides)

	if self.case_fn then
		return self.case_fn(x, o)
	end

	local mesh = self.mesh_fn(x, o)
	local reg = self.registry_fn(x, o)
	local alg = self.algorithm_fn(x, o)
	local bcs = self.bcs_fn and self.bcs_fn(x, o) or {}

	return Case.new(reg, alg, mesh, bcs)
end

function FvmStudy:show_mesh(arg)
	local mesh = self:build_mesh(arg)
	ui.display_mesh(mesh)
	return mesh
end

function FvmStudy:inspect_registry(arg)
	local reg = self:build_registry(arg)
	print(reg:listing())
	return reg
end

function FvmStudy:inspect_deps(arg)
	local reg = self:build_registry(arg)
	print(reg:dep_listing())
	return reg
end

function FvmStudy:inspect_algorithm(arg)
	local case = self:build_case(arg)
	case:print_algorithm()
	return case.compiled.expanded_alg
end

function FvmStudy:inspect_instructions(arg)
	local case = self:build_case(arg)
	case:print_instructions()
	return case.compiled.instructions
end

function FvmStudy:inspect_resources(arg)
	local case = self:build_case(arg)
	case:print_resources()
	return case.compiled.manifest
end

function FvmStudy:inspect_warnings(arg)
	local case = self:build_case(arg)
	case:print_warnings()
	return case
end

function FvmStudy:default_evaluate(x, opts)
	local case = self:build_case(x)
	local sim = case:make_sim()

	local all_opts = {}
	for k, v in pairs(opts) do all_opts[k] = v end
	for k, v in pairs(x) do all_opts[k] = v end

	sim:run()

	local res = {
		x = x,
		opts = all_opts,
		case = case,
		sim = sim,
		mesh = case.mesh,

		field = function(name)
			return case:field(name)
		end,

		fields = function()
			return case:fields()
		end,
	}

	return setmetatable(res, {
		__tostring = function(r)
			local parts = {}
			local names = r.sim.diag.system_names and r.sim.diag.system_names() or {}

			for _, name in ipairs(names) do
				local resid = r.sim.diag.residual(name)
				if resid then
					parts[#parts + 1] = string.format("%s=%.3e", E.pretty_sym(name), resid)
				end
			end

			table.sort(parts)

			local res_str = #parts > 0 and table.concat(parts, "  ") or "no residuals"

			return string.format(
				"<result: %s | iters=%d | %s>",
				tostring(r.mesh),
				r.sim.diag.iter(),
				E.pretty_sym(res_str)
			)
		end
	})
end

function FvmStudy:install(repl)
	if self._fvm_installed then
		return base.Study.install(self, repl)
	end

	self._fvm_installed = true

	if self.mesh_fn then
		self:expose("build-mesh", function(arg)
			return self:build_mesh(arg)
		end, "Build the mesh for the current design", { hidden = true })

		self:expose("show-mesh", function(arg)
			return self:show_mesh(arg)
		end, "Build and display the mesh", { hidden = true })
	end

	if self.registry_fn then
		self:expose("build-registry", function(arg)
			return self:build_registry(arg)
		end, "Build the physics registry", { hidden = true })

		self:expose("inspect-registry", function(arg)
			return self:inspect_registry(arg)
		end, "Print the registry listing", { hidden = true })

		self:expose("inspect-deps", function(arg)
			return self:inspect_deps(arg)
		end, "Print the registry dependency listing", { hidden = true })
	end

	if self.algorithm_fn then
		self:expose("build-algorithm", function(arg)
			return self:build_algorithm(arg)
		end, "Build the algorithm", { hidden = true })

		self:expose("inspect-algorithm", function(arg)
			return self:inspect_algorithm(arg)
		end, "Print the expanded algorithm", { hidden = true })
	end

	if self.case_fn or self.mesh_fn and self.registry_fn and self.algorithm_fn then
		self:expose("build-case", function(arg)
			return self:build_case(arg)
		end, "Compile the FVM case without running it", { hidden = true })

		self:expose("inspect-instructions", function(arg)
			return self:inspect_instructions(arg)
		end, "Print compiled FVM instructions", { hidden = true })

		self:expose("inspect-resources", function(arg)
			return self:inspect_resources(arg)
		end, "Print compiled resource counts", { hidden = true })

		self:expose("inspect-warnings", function(arg)
			return self:inspect_warnings(arg)
		end, "Print compile warnings", { hidden = true })
	end

	if not self.evaluate_fn and (self.case_fn or self.mesh_fn and self.registry_fn and self.algorithm_fn) then
		self:evaluate(function(x, opts)
			return self:default_evaluate(x, opts)
		end, {
			doc = "Build, run, and return the FVM result",
		})
	end

	return base.Study.install(self, repl)
end

--
-- API
--

M._api = {
	new = {
		args = "title:string?",
		ret = "FvmStudy",
		doc = "Create an FVM REPL study object",
	},
}

M._types = {
	FvmStudy = {
		kind = "table",
		constructor = "jnl.fvm.study.new(title)",
		doc = "FVM-specific study object with automatic case builders and inspectors",
		methods = {
			mesh = {
				args = "fn:function, opts:table?",
				ret = "FvmStudy",
				doc = "Register a mesh builder fn(design, opts) -> Mesh",
			},
			registry = {
				args = "fn:function, opts:table?",
				ret = "FvmStudy",
				doc = "Register a registry builder fn(design, opts) -> Registry",
			},
			algorithm = {
				args = "fn:function, opts:table?",
				ret = "FvmStudy",
				doc = "Register an algorithm builder fn(design, opts) -> Algorithm",
			},
			bcs = {
				args = "fn:function, opts:table?",
				ret = "FvmStudy",
				doc = "Register a boundary-condition builder fn(design, opts) -> table",
			},
			case = {
				args = "fn:function, opts:table?",
				ret = "FvmStudy",
				doc = "Register a custom case builder fn(design, opts) -> Case",
			},
			build_mesh = {
				args = "design_overrides:table?",
				ret = "Mesh",
				doc = "Build the mesh for a design",
			},
			build_registry = {
				args = "design_overrides:table?",
				ret = "Registry",
				doc = "Build the registry for a design",
			},
			build_algorithm = {
				args = "design_overrides:table?",
				ret = "Algorithm",
				doc = "Build the algorithm for a design",
			},
			build_bcs = {
				args = "design_overrides:table?",
				ret = "table",
				doc = "Build boundary conditions for a design",
			},
			build_case = {
				args = "design_overrides:table?",
				ret = "Case",
				doc = "Build and compile an FVM case without running it",
			},
			build_case_with = {
				args = "design_overrides:table, option_overrides:table ",
				ret = "Case",
				doc = "Build and compile an FVM case with option overrides",
			},
			show_mesh = {
				args = "design_overrides:table?",
				ret = "Mesh",
				doc = "Build and display the mesh in the UI",
			},
			inspect_registry = {
				args = "design_overrides:table?",
				ret = "Registry",
				doc = "Print the registry listing and return it",
			},
			inspect_deps = {
				args = "design_overrides:table?",
				ret = "Registry",
				doc = "Print the registry dependency listing and return it",
			},
			inspect_algorithm = {
				args = "design_overrides:table?",
				ret = "Case",
				doc = "Build the case, print the expanded algorithm used for compilation, and return the case",
			},
			inspect_instructions = {
				args = "design_overrides:table?",
				ret = "Case",
				doc = "Print compiled FVM instructions and return the case",
			},
			inspect_resources = {
				args = "design_overrides:table?",
				ret = "Case",
				doc = "Print compiled resource counts and return the case",
			},
			inspect_warnings = {
				args = "design_overrides:table?",
				ret = "Case",
				doc = "Print compile warnings and return the case",
			},
			default_evaluate = {
				args = "design:table, opts:table",
				ret = "table",
				doc = "Build, run, and return a standard result table",
			},
			install = {
				args = "repl:Repl?",
				ret = "Repl",
				doc = "Install FVM inspectors and generic study helpers into a REPL",
			},
		},
	},
}

return M
