-- fvm/core/registry.lua - registry of symbols for physics problems
-- <jed@nelson.ac> // 2026-05-11

-- deps
local E = require("jnl.core.expr")
local G = require("jnl.core.glyphs")
local V = require("jnl.core.validation")

--
-- Types of things that go into registry
--

local Constant = {}
Constant.__index = Constant

function Constant:_pretty()
	return string.format("%-12s %g", self.name, self.value)
end

local Expression = {}
Expression.__index = Expression

function Expression:_pretty()
	return string.format("%-12s %s", self.name, self.expr)
end

local Correction = {}
Correction.__index = Correction

function Correction:_pretty()
	return string.format("%-12s [correction] %s <- %s",
		"__correct_" .. self.target,
		self.target,
		self.expr)
end

local Field = {}
Field.__index = Field

function Field:_pretty()
	local lines = {}
	local function line(s) lines[#lines + 1] = s end

	-- header
	local flags = {}
	if self.region then flags[#flags + 1] = "region:" .. self.region end
	local flag_str = #flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or ""
	line(self.name .. flag_str)

	if self.passive then
		line(self.name .. "  [passive - correction driven]")
		return table.concat(lines, "\n")
	end

	-- equation block
	if self.eq and self.eq._pretty then
		line(self.eq:_pretty(self.name, G.indent))
	end

	-- solver properties
	if self.eq then
		local props = {
			{ "solver", self.eq.solver or "?" },
			{ "relax",  self.eq.relax and string.format("%g", self.eq.relax) or "none" },
		}

		-- bcs takes precedent over bcs_from
		if self.bcs then
			props[#props + 1] = { "bcs", "<bc-table>" }
		elseif self.bcs_from then
			props[#props + 1] = { "bcs_from", self.bcs_from }
		end

		if self.region then props[#props + 1] = { "region", self.region } end

		local max_k = 0
		for _, p in ipairs(props) do
			if #p[1] > max_k then max_k = #p[1] end
		end
		for _, p in ipairs(props) do
			local pad = string.rep(" ", max_k - #p[1])
			line(G.indent .. p[1] .. pad .. "  " .. p[2])
		end
	end

	return table.concat(lines, "\n")
end

local Uniform = {}
Uniform.__index = Uniform

local Vector = {}
Vector.__index = Vector

function Vector:_pretty()
	return string.format("%-12s vector(%s)", self.name,
		table.concat(self.components, ", "))
end

local Intermediate = {}
Intermediate.__index = Intermediate

function Intermediate:_pretty()
	local dep_str = #self.deps > 0
		and table.concat(self.deps, ", ") or "-"
	return string.format("%-12s [synthetic: %s] <- %s",
		self.name, self.itype, dep_str)
end

--
-- Registry: just a table of syms
--

local R = {}
R.__index = R

function R.new()
	return setmetatable({}, R)
end

function R:define(name, sym, proto)
	proto = proto or {}
	sym._type = "sym"
	sym.name = name
	self[name] = setmetatable(sym, proto)
end

function R:constant(name, value)
	V.identifier(name, "R:constant name")
	V.typeof(value, "number", "constant value")
	self:define(name, { kind = "constant", value = value }, Constant)
end

-- TODO: figure out the interface
-- has effect that if it's used in any FVM or further things then you have to
-- call different methods etc (ie laplacian_region(k_air) AND laplacian_region(k_solid))
-- function R:region_property(sym, spec)
-- end

function R:expression(name, expr)
	V.identifier(name, "R:expression name")
	self:define(name, { kind = "expression", expr = expr }, Expression)
end

function R:correction(name, expr)
	V.identifier(name, "R:correction target")
	assert(E.is_expr(expr),
		"R:correction: expected an expression for '" .. name .. "'")
	local sym_name = "__correct_" .. name
	self:define(sym_name, {
		kind   = "correction",
		target = name,
		expr   = expr,
	}, Correction)
end

function R:field(name, spec)
	spec = spec or {}
	V.field_name(name, "R:field name")

	if spec.region ~= nil then
		V.typeof(spec.region, "string", "field '" .. name .. "' region")
	end

	if spec.bcs_from ~= nil then
		V.field_name(spec.bcs_from, "field '" .. name .. "' bcs_from")
	end

	self:define(name, {
		kind = "field",
		passive = spec.eq == nil,
		initial = spec.initial or 0.0,
		bcs = spec.bcs,
		bcs_from = spec.bcs_from,
		region = spec.region,
		eq = spec.eq,
		clip = spec.clip,
	}, Field)
end

function R:uniform(name, value)
	V.field_name(name, "R:uniform name")
	V.typeof(value, "number", "uniform value")
	self:define(name, {
		kind = "uniform",
		value = value,
	}, Uniform)
end

function R:vector(name, components)
	V.field_name(name, "R:vector name")
	assert(type(components) == "table" and #components >= 2,
		"R:vector components: must be a list of at least 2 field names")
	for _, c in ipairs(components) do
		assert(self[c],
			"R:vector '" .. name .. "': component '" .. c .. "' not yet registered")
	end
	self:define(name, { kind = "vector", components = components }, Vector)
end

--- Add an Intermediate to registry, for use by compiler backend.
function R:intermediate(name, itype, deps, opts)
	V.internal_identifier(name, "R:intermediate name")
	opts = opts or {}
	self:define(name, {
		kind = "intermediate",
		itype = itype,
		deps = deps,
		accessor = opts.accessor or false, -- accessor means "invisible to algorithm" eg diag
	}, Intermediate)
end

--
-- Mutation
--

function R:add_term(field_name, term)
	local sym = self:expect(field_name)
	assert(sym.kind == "field" and sym.eq,
		"R:add_term: '" .. field_name .. "' has no equation")
	sym.eq.terms[#sym.eq.terms + 1] = term
	for dep in pairs(term._deps or {}) do
		sym.eq._deps[dep] = true
	end
end

function R:set_relax(field_name, alpha)
	local sym = self:expect(field_name)
	assert(sym.kind == "field" and sym.eq,
		"R:set_relax: '" .. field_name .. "' has no equation")
	sym.eq.relax = alpha
end

function R:set_solver(field_name, solver)
	local sym = self:expect(field_name)
	assert(sym.kind == "field" and sym.eq,
		"R:set_solver: '" .. field_name .. "' has no equation")
	sym.eq.solver = solver
end

function R:set_initial(field_name, value)
	local sym = self:expect(field_name)
	assert(sym.kind == "field",
		"R:set_initial: '" .. field_name .. "' is not a field")
	sym.initial = value
end

--
-- Helpers
--

function R:query(name)
	return self[name]
end

function R:expect(name)
	local sym = self[name]
	assert(sym, "registry: unknown symbol '" .. name .. "'")
	return sym
end

function R:listing()
	local parts = {}
	local names = {}
	for name in pairs(self) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		parts[#parts + 1] = self[name]:_pretty()
	end
	return table.concat(parts, "\n")
end

function R:print()
	print(self:listing())
end

function R:deps_of(name)
	local sym = self:expect(name)
	local into = {}

	if sym.kind == "constant" then
		return {}
	elseif sym.kind == "expression" then
		local names = sym.expr:deps()
		for _, n in ipairs(names) do into[n] = true end
	elseif sym.kind == "correction" then
		local names = sym.expr:deps()
		for _, n in ipairs(names) do into[n] = true end
	elseif sym.kind == "field" and sym.eq then
		for n in pairs(sym.eq._deps or {}) do into[n] = true end
	elseif sym.kind == "intermediate" then
		for _, n in ipairs(sym._deps or {}) do into[n] = true end
	end

	local result = {}
	for n in pairs(into) do result[#result + 1] = n end
	table.sort(result)
	return result
end

function R:depends_on(name)
	local result = {}
	for other_name in pairs(self) do
		local deps = self:deps_of(other_name)
		for _, d in ipairs(deps) do
			if d == name then
				result[#result + 1] = other_name
				break
			end
		end
	end

	table.sort(result)
	return result
end

function R:dep_listing()
	local lines = {}
	local names = {}
	for name in pairs(self) do names[#names + 1] = name end
	table.sort(names)

	for _, name in ipairs(names) do
		local deps = self:deps_of(name)
		local dep_str = #deps > 0 and table.concat(deps, ", ") or "-"
		lines[#lines + 1] = string.format("%-12s -> { %s }", name, dep_str)
	end

	return table.concat(lines, "\n")
end

--- Validates that all symbols in the registry are correctly accounted for.
function R:validate()
	local errors = {}

	for name, sym in pairs(self) do
		if type(sym) ~= "table" then goto continue end

		local deps = self:deps_of(name)
		for _, dep in ipairs(deps) do
			if not self[dep] then
				errors[#errors + 1] = string.format(
					"  '%s' depends on unregistered symbol '%s'", name, dep)
			end
		end

		if sym.kind == "correction" then
			local target = self[sym.target]
			if not target then
				errors[#errors + 1] = string.format(
					"  correction '%s' targets unregistered field '%s'",
					name, sym.target)
			elseif target.kind ~= "field" then
				errors[#errors + 1] = string.format(
					"  correction '%s' targets '%s' which is a %s, not a field",
					name, sym.target, target.kind)
			end
		end

		::continue::
	end

	if #errors > 0 then
		error("registry validation failed:\n" .. table.concat(errors, "\n"), 2)
	end
end

--
-- Metamethods
--

function R:__tostring()
	local counts = {
		constant = 0,
		field = 0,
		expression = 0,
		correction = 0,
		uniform = 0,
		vector = 0,
		intermediate = 0,
	}

	for _, sym in pairs(self) do
		if type(sym) == "table" and sym.kind and counts[sym.kind] ~= nil then
			counts[sym.kind] = counts[sym.kind] + 1
		end
	end

	return string.format(
		"jnl.core.Registry(%d fields, %d constants, %d expressions, %d corrections, %d intermediates)",
		counts.field,
		counts.constant,
		counts.expression,
		counts.correction,
		counts.intermediate
	)
end

--
-- API
--

R._doc = "Registry of named symbols for a CFD physics problem: fields, constants, expressions, and corrections."

R._doc_subsection =
	"Register constants, fields, and expressions in dependency order; forward references " ..
	"are not allowed. Fields from canned registries can be amended with add_term, " ..
	"set_relax, set_solver, and set_initial rather than re-registering. Call validate() " ..
	"before handing the registry to an algorithm to catch missing deps early."

R._api = {
	-- construction
	new          = { args = "", ret = "Registry", doc = "Create an empty registry" },
	define       = { args = "name, sym, proto?", ret = "nil", doc = "Low-level symbol insert; sets name and _type on sym" },
	-- symbol registration
	constant     = { args = "name, value", ret = "nil", doc = "Register a named numeric constant" },
	uniform      = { args = "name, value", ret = "nil", doc = "Register a uniform field initialised to value; emitted as a pre-step" },
	field        = { args = "name, spec?", ret = "nil", doc = "Register a field; spec: { eq, bcs, bcs_from, initial, region, clip }" },
	vector       = { args = "name, components", ret = "nil", doc = "Register a named vector over already-registered scalar fields" },
	expression   = { args = "name, expr", ret = "nil", doc = "Register a derived expression; re-evaluated when deps change" },
	correction   = { args = "name, expr", ret = "nil", doc = "Register a correction for field 'name'; stored as __correct_<name>" },
	intermediate = { args = "name, itype, deps, opts?", ret = "nil", doc = "Register a compiler-managed synthetic; opts: { accessor=false }" },
	-- amendment
	add_term     = { args = "field, term", ret = "nil", doc = "Append a term to an existing field equation and merge its deps" },
	set_relax    = { args = "field, alpha", ret = "nil", doc = "Set under-relaxation factor on an existing field equation" },
	set_solver   = { args = "field, solver", ret = "nil", doc = "Set linear solver on an existing field equation" },
	set_initial  = { args = "field, value", ret = "nil", doc = "Set initial field value" },
	-- query
	query        = { args = "name", ret = "sym?", doc = "Return symbol or nil if absent" },
	expect       = { args = "name", ret = "sym", doc = "Return symbol or error if absent" },
	deps_of      = { args = "name", ret = "string[]", doc = "Direct dependencies of a symbol" },
	depends_on   = { args = "name", ret = "string[]", doc = "All symbols that directly depend on name" },
	validate     = { args = "", ret = "nil", doc = "Error if any symbol has missing deps or malformed corrections" },
	-- display
	listing      = { args = "", ret = "string", doc = "Pretty-printed symbol table sorted by name" },
	dep_listing  = { args = "", ret = "string", doc = "Dependency listing: each symbol with its direct deps" },
	print        = { args = "", ret = "nil", doc = "Print listing() to stdout" },
	__tostring   = {
		args = "self",
		ret = "string",
		doc = "Return a compact one-line registry summary for REPL display",
	},
}

R._types = {
	sym = {
		doc         = "Tagged symbol table stored in the registry; kind field selects behaviour",
		constructor = "R:field / R:constant / R:expression etc.",
		kind        = "table",
		methods     = {
			_pretty = { args = "", ret = "string", doc = "Human-readable one-line (or block) description of the symbol" },
		},
	},
}

return R
