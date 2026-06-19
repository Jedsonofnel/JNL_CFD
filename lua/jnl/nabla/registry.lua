-- jnl/nabla/registry.lua - registry of field declarations for physics problems
-- <jed@nelson.ac> // 2026-06-04

local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")
local Node = require("jnl.nabla.node")
local Equation = require("jnl.nabla.equation")

--
-- Registry
--

--- Declare fields, constants, governing equations, and derived expressions for
--- a symbolic physics model.
---
--- A registry stores named symbolic fields in declaration order. Field
--- declarations return injected `Node` instances with chainable methods such as
--- `governed_by`, `defined_as`, `prescribed`, and `initial`.
---@class Registry
---@field label string? Human-readable registry label.
---@field entries table<string, RegistryEntry> Field entries by name.
---@field order string[] Declaration order.
local Registry = {}
Registry.__index = Registry

--- Metadata for one declared registry symbol.
---@class RegistryEntry
---@field name string Symbol name.
---@field rank integer Tensor rank.
---@field node Node Symbol node.
---@field kind? string Entry kind, currently `"const"` for constants.
---@field value? number Constant scalar value.
---@field initial? number Initial or prescribed value.
---@field solve? boolean True for prognostic fields, false for diagnostic fields.
---@field is_prescribed? boolean True when the field is externally prescribed.
---@field equation? Equation Governing equation.
---@field expr? Node Diagnostic expression.
---@field correction? Node Correction expression.
---@field clip? number[] Lower and upper clipping limits.

--- A registry field node with chainable declaration helpers injected.
---@class RegistryField: Node
---@field governed_by fun(self: RegistryField, eq: Equation): RegistryField Mark this field as governed by an equation.
---@field defined_as fun(self: RegistryField, expr: Node): RegistryField Define this field diagnostically.
---@field prescribed fun(self: RegistryField, value: number): RegistryField Mark this field as externally prescribed.
---@field correction fun(self: RegistryField, expr: Node): RegistryField Attach a correction expression.
---@field add_lhs fun(self: RegistryField, expr: Node): RegistryField Add a term to the equation left-hand side.
---@field add_rhs fun(self: RegistryField, expr: Node): RegistryField Add a term to the equation right-hand side.
---@field initial fun(self: RegistryField, value: number): RegistryField Set the initial value.
---@field clip fun(self: RegistryField, lo: number, hi?: number): RegistryField Set clipping limits.

-- Dependency scanning

local function scan_node(node, value_deps, matrix_deps, self_name)
	if not node or type(node) ~= "table" then return end

	if node:is_leaf() then
		if node.kind == "symbol" and node.name ~= self_name then
			value_deps[node.name] = true
		end
		return
	end

	scan_node(node.a, value_deps, matrix_deps, self_name)
	scan_node(node.b, value_deps, matrix_deps, self_name)
end

local function scan_equation(eq, value_deps, matrix_deps, self_name)
	scan_node(eq.lhs, value_deps, matrix_deps, self_name)
	scan_node(eq.rhs, value_deps, matrix_deps, self_name)
end

--
-- Per-instance method injection
--

---@return RegistryField
local function inject(node, reg)
	local name = node.name

	-- copy node fields into new table, metatable IS Node
	local inst = {}
	for k, v in pairs(node) do inst[k] = v end
	setmetatable(inst, Node) -- is_node(inst) returns true, unchanged

	-- injected methods sit directly on the instance table
	-- they shadow Node class methods via normal Lua lookup
	local entry = reg.entries[name]

	inst.governed_by = function(_, eq)
		assert(getmetatable(eq) == Equation,
			string.format("governed_by '%s': expected Equation", name))
		entry.equation = eq
		entry.solve    = true
		return inst
	end

	inst.defined_as = function(_, expr)
		assert(Node.is_node(expr),
			string.format("defined_as '%s': expected Node", name))
		entry.expr  = expr
		entry.solve = false
		return inst
	end

	inst.prescribed = function(_, value)
		V.typeof(value, "number",
			string.format("prescribed '%s' value", name))
		entry.initial       = value
		entry.solve         = false
		entry.is_prescribed = true
		return inst
	end

	inst.correction = function(_, expr)
		assert(Node.is_node(expr),
			string.format("correction '%s': expected Node", name))
		entry.correction = expr
		return inst
	end

	inst.add_lhs = function(_, expr)
		assert(Node.is_node(expr),
			string.format("add_lhs '%s': expected Node", name))
		assert(entry.equation,
			string.format("add_lhs '%s': no governing equation yet", name))
		entry.equation = Equation.new(entry.equation.lhs + expr, entry.equation.rhs)
		return inst
	end

	inst.add_rhs = function(_, expr)
		assert(Node.is_node(expr),
			string.format("add_rhs '%s': expected Node", name))
		assert(entry.equation,
			string.format("add_rhs '%s': no governing equation yet", name))
		entry.equation = Equation.new(entry.equation.lhs, entry.equation.rhs + expr)
		return inst
	end

	inst.initial = function(_, value)
		V.typeof(value, "number",
			string.format("initial '%s': expected number", name))
		entry.initial = value
		return inst
	end

	inst.clip = function(_, lo, hi)
		hi = hi or math.huge -- hi is optional
		assert(type(lo) == "number" and type(hi) == "number",
			string.format("clip '%s': expected two numbers", name))
		assert(lo < hi,
			string.format("clip '%s': lo must be less than hi", name))
		entry.clip = { lo, hi }
		return inst
	end

	return inst
end

-- Construction

--- Create a new registry.
---@param label? string Human-readable label.
---@return Registry registry
function Registry.new(label)
	return setmetatable({
		label   = label,
		entries = {},
		order   = {},
	}, Registry)
end

local function declare(reg, name, rank)
	V.identifier(name, "registry declaration")
	assert(not reg.entries[name],
		string.format("registry: '%s' already declared", name))

	local node = Node.tensor(name, rank)
	local entry = {
		name = name,
		rank = rank,
		node = node,
		initial = 0,
	}

	reg.entries[name] = entry
	reg.order[#reg.order + 1] = name
	return inject(node, reg)
end

--- Declare a scalar field.
---@param name string Field name.
---@return RegistryField field
function Registry:scalar(name) return declare(self, name, 0) end

--- Declare a vector field.
---@param name string Field name.
---@return RegistryField field
function Registry:vector(name) return declare(self, name, 1) end

--- Declare a tensor field.
---@param name string Field name.
---@param rank? integer Tensor rank; defaults to 2.
---@return RegistryField field
function Registry:tensor(name, rank) return declare(self, name, rank or 2) end

--- Declare a named scalar constant.
---@param name string Constant name.
---@param value number Constant value.
---@return Node node
function Registry:const(name, value)
	V.identifier(name, "registry const name")
	V.typeof(value, "number", "registry const value")
	assert(not self.entries[name],
		string.format("registry: '%s' already declared", name))

	local node = Node.const(name, value)
	local entry = { name = name, rank = 0, node = node, kind = "const", value = value }
	self.entries[name] = entry
	self.order[#self.order + 1] = name
	return node
end

--- Declare a named constant vector.
---@param name string Constant vector name.
---@param ... number Vector components.
---@return Node node
function Registry:cvec(name, ...)
	V.identifier(name, "registry cvec name")
	assert(not self.entries[name],
		string.format("registry: '%s' already declared", name))

	local node = Node.const(name, ...)
	assert(node.rank == 1, "cvec: expected 2 or 3 number components")

	local entry = { name = name, rank = 1, node = node, kind = "const" }
	self.entries[name] = entry
	self.order[#self.order + 1] = name
	return node
end

--
-- Registry-level amendment
--

--- Return an injected field node by name.
---@param name string Field name.
---@return RegistryField field
function Registry:get(name)
	local e = self.entries[name]
	assert(e, string.format("registry: unknown symbol '%s'", name))
	return inject(e.node, self)
end

--- Return a registry entry by name, raising an error if absent.
---@param name string Field name.
---@return RegistryEntry entry
function Registry:expect(name)
	local e = self.entries[name]
	assert(e, string.format("registry: unknown symbol '%s'", name))
	return e
end

--- Return a registry entry by name, or nil if absent.
---@param name string Field name.
---@return RegistryEntry? entry
function Registry:entry(name)
	return self.entries[name]
end

--- Set the initial value for a declared field.
---@param name string Field name.
---@param value number Initial value.
function Registry:set_initial(name, value)
	self:expect(name).initial = value
end

--- Set clipping limits for a declared field.
---@param name string Field name.
---@param lo number Lower bound.
---@param hi number Upper bound.
function Registry:set_clip(name, lo, hi)
	assert(lo < hi, "set_clip: lo must be less than hi")
	self:expect(name).clip = { lo, hi }
end

--
-- Iteration
--

--- Iterate over entries in declaration order.
---@param fn fun(name: string, entry: RegistryEntry)
function Registry:each(fn)
	for _, name in ipairs(self.order) do
		fn(name, self.entries[name])
	end
end

--- Return names of fields solved from governing equations.
---@return string[] names
function Registry:prognostics()
	local out = {}
	for _, name in ipairs(self.order) do
		if self.entries[name].solve == true then out[#out + 1] = name end
	end
	return out
end

--- Return names of diagnostic fields defined by expressions.
---@return string[] names
function Registry:diagnostics()
	local out = {}
	for _, name in ipairs(self.order) do
		local e = self.entries[name]
		if e.solve == false and not e.is_prescribed and e.kind ~= "const" then
			out[#out + 1] = name
		end
	end
	return out
end

--- Return names of externally prescribed fields.
---@return string[] names
function Registry:prescribed_fields()
	local out = {}
	for _, name in ipairs(self.order) do
		if self.entries[name].is_prescribed then out[#out + 1] = name end
	end
	return out
end

-- Dependency queries

--- Return dependency sets for a field.
---@param name string Field name.
---@return table deps
function Registry:deps_of(name)
	local e = self:expect(name)

	local eq_value, eq_matrix = {}, {}
	local cor_value, cor_matrix = {}, {}

	if e.equation then
		scan_equation(e.equation, eq_value, eq_matrix, name) -- pass self_name
	elseif e.expr then
		scan_node(e.expr, eq_value, eq_matrix, name)
	end

	if e.correction then
		scan_node(e.correction, cor_value, cor_matrix, nil) -- no self filter
	end

	return {
		equation = { value = eq_value, matrix = eq_matrix },
		correction = { value = cor_value, matrix = cor_matrix },
	}
end

--
-- Validation
--

--- Validate declarations, dependencies, and equation ranks.
function Registry:validate()
	local errors = {}
	for _, name in ipairs(self.order) do
		local e = self.entries[name]
		if e.kind == "const" then goto continue end

		local deps = self:deps_of(name)

		-- check equation value deps exist
		for dep in pairs(deps.equation.value) do
			if not self.entries[dep] then
				errors[#errors + 1] = string.format(
					"  '%s' depends on undeclared '%s'", name, dep)
			end
		end

		-- check equation matrix deps exist
		for dep in pairs(deps.equation.matrix) do
			if not self.entries[dep] then
				errors[#errors + 1] = string.format(
					"  '%s' needs assembly of undeclared '%s'", name, dep)
			end
		end

		-- check correction deps exist
		for dep in pairs(deps.correction.value) do
			if not self.entries[dep] then
				errors[#errors + 1] = string.format(
					"  '%s' correction depends on undeclared '%s'", name, dep)
			end
		end

		if e.solve == true and not e.equation then
			errors[#errors + 1] = string.format(
				"  '%s' is prognostic but has no governing equation", name)
		end

		if e.equation then
			if e.equation.lhs.rank ~= e.equation.rhs.rank then
				errors[#errors + 1] = string.format(
					"  '%s' equation rank mismatch: lhs=%d rhs=%d",
					name, e.equation.lhs.rank, e.equation.rhs.rank)
			end
		end

		::continue::
	end

	if #errors > 0 then
		error("registry validation failed:\n" .. table.concat(errors, "\n"), 2)
	end
end

--
-- Display
--

local function section(out, title, names, fn)
	if #names == 0 then return end
	out[#out + 1] = title
	for _, name in ipairs(names) do fn(name) end
	out[#out + 1] = ""
end

--- Return a multi-line listing of constants, diagnostics, prescribed fields, and prognostics.
---@return string text
function Registry:listing()
	local indent = G.indent
	local sep = ""
	local label = self.label and (" [" .. self.label .. "]") or ""
	local out = { "Registry" .. label, sep }

	-- constants
	local const_names = {}
	for _, name in ipairs(self.order) do
		if self.entries[name].kind == "const" then
			const_names[#const_names + 1] = name
		end
	end
	section(out, "  constants", const_names, function(name)
		local e = self.entries[name]
		if e.node and e.node.kind == "cvec" then
			out[#out + 1] = string.format("%s  %-12s = %s",
				indent, name, tostring(e.node))
		else
			out[#out + 1] = string.format("%s  %-12s = %g",
				indent, name, e.value)
		end
	end)

	-- diagnostic
	section(out, "  diagnostic", self:diagnostics(), function(name)
		local e = self.entries[name]
		out[#out + 1] = string.format("%s  %-12s = %s",
			indent, name, e.expr and tostring(e.expr) or "[undefined]")
	end)

	-- prescribed
	section(out, "  prescribed", self:prescribed_fields(), function(name)
		local e = self.entries[name]
		out[#out + 1] = string.format("%s  %-12s = %g  [fixed]",
			indent, name, e.initial)
	end)

	-- prognostic
	section(out, "  prognostic", self:prognostics(), function(name)
		local e = self.entries[name]
		if e.equation then
			out[#out + 1] = string.format("%s  %-12s : %s",
				indent, name, tostring(e.equation))
		else
			out[#out + 1] = string.format("%s  %-12s : [no equation]",
				indent, name)
		end
		local flags = {}
		if e.initial ~= 0 then
			flags[#flags + 1] = "initial=" .. e.initial
		end
		if e.clip then
			flags[#flags + 1] = string.format("clip=[%g,%s]",
				e.clip[1], e.clip[2] == math.huge and "∞" or e.clip[2])
		end
		if #flags > 0 then
			out[#out + 1] = string.format("%s  %-12s   %s",
				indent, "", table.concat(flags, "  "))
		end
		if e.correction then
			out[#out + 1] = string.format("%s  %-12s   correction: %s",
				indent, "", tostring(e.correction))
		end
	end)

	return table.concat(out, "\n")
end

--- Return a multi-line dependency listing.
---@return string text
function Registry:dep_listing()
	local lines = {}
	for _, name in ipairs(self.order) do
		if self.entries[name].kind == "const" then goto continue end

		local deps                = self:deps_of(name)
		local vlist, mlist, clist = {}, {}, {}

		for d in pairs(deps.equation.value) do vlist[#vlist + 1] = d end
		for d in pairs(deps.equation.matrix) do mlist[#mlist + 1] = d end
		for d in pairs(deps.correction.value) do clist[#clist + 1] = d end

		table.sort(vlist); table.sort(mlist); table.sort(clist)

		local parts = {}
		if #vlist > 0 then
			parts[#parts + 1] = "value:{" .. table.concat(vlist, ",") .. "}"
		end
		if #mlist > 0 then
			parts[#parts + 1] = "matrix:{" .. table.concat(mlist, ",") .. "}"
		end
		if #clist > 0 then
			parts[#parts + 1] = "correction:{" .. table.concat(clist, ",") .. "}"
		end

		lines[#lines + 1] = string.format("  %-12s -> %s",
			name, #parts > 0 and table.concat(parts, "  ") or "-")

		::continue::
	end
	return "Dependencies\n" .. table.concat(lines, "\n")
end

--- Return a compact registry summary.
---@return string text
function Registry:__tostring()
	local label = self.label and (" [" .. self.label .. "]") or ""
	return string.format("Registry%s  prog=%d  diag=%d  prescribed=%d  const=%d",
		label,
		#self:prognostics(),
		#self:diagnostics(),
		#self:prescribed_fields(),
		(function()
			local n = 0
			for _, name in ipairs(self.order) do
				if self.entries[name].kind == "const" then n = n + 1 end
			end
			return n
		end)())
end

return Registry
