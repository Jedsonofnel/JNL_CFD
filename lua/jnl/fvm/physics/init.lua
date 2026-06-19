-- jnl/fvm/physics/init.lua - Physics object constructor
-- <jed@nelson.ac> // 2026-06-16

-- deps
local Nabla = require("jnl.nabla")
local Node = Nabla.Node
local P = require("jnl.fvm.physics.plan")
local V = require("jnl.core.validation")

--- Physics library for declaring registry + algorithm in one.
local Physics = {}
Physics.__index = Physics

--- Create a new physics object.
---@param name string?
function Physics.new(name)
	return setmetatable({
		name = name,
		reg = Nabla.new_registry(),
	}, Physics)
end

--
-- Registry re-export
--

--- Declare a scalar field.
---@param name string Field name.
---@return RegistryField field
function Physics:scalar(name)
	return self.reg:scalar(name)
end

--- Declare a vector field.
---@param name string Field name.
---@return RegistryField field
function Physics:vector(name)
	return self.reg:vector(name)
end

--- Declare a tensor field.
---@param name string Field name.
---@param rank? integer Tensor rank; defaults to 2.
---@return RegistryField field
function Physics:tensor(name, rank)
	rank = rank or 2
	return self.reg:tensor(name, rank)
end

--- Declare a named scalar constant.
---@param name string Constant name.
---@param value number Constant value.
---@return Node node
function Physics:const(name, value)
	return self.reg:const(name, value)
end

--- Declare a named constant vector.
---@param name string Constant vector name.
---@param ... number Vector components.
---@return Node node
function Physics:cvec(name, ...)
	return self.reg:cvec(name, ...)
end

--
-- Algorithm builder
--

local Builder = {}
Builder.__index = Builder

function Builder.new()
	return setmetatable({
		root = P.new_root(),
		last = nil,
	}, Builder)
end

local function push(b, plan)
	b.root:push(plan)
	b.last = plan
	return b
end

local function fname(v)
	if type(v) == "string" then return v end
	if Node.is_node(v) and v.name then return v.name end
	error("alg: expected field name or named Node, got " .. type(v), 3)
end

--- Fill a field with a constant value before the main loop begins.
---@param field string|Node Field name or Node.
---@param value number Fill value.
---@return AlgBuilder self
function Builder:fill(field, value)
	field = fname(field)
	V.identifier(field, "alg:fill field")
	V.typeof(value, "number", "alg:fill value")
	return push(self, { op = "fill", field = field, value = value })
end

--- Assemble and solve the linear system for a field.
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:solve(field)
	field = fname(field)
	V.identifier(field, "alg:solve")
	return push(self, { op = "solve", field = field })
end

--- Evaluate a diagnostic field expression explicitly.
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:evaluate(field)
	field = fname(field)
	V.identifier(field, "alg:evaluate")
	return push(self, { op = "evaluate", field = field })
end

--- Insert a nested correction loop inside the current phase.
---
--- The callback receives a fresh AlgBuilder for the inner steps. Returns the
--- inner Algorithm so it can be further configured (e.g. to set inner tolerances):
---
---     b:solve("U")
---     local inner = b:inner(function(ib)
---         ib:solve("p")
---         ib:correct("U")
---     end, 3)
---
---@param cb AlgBuilderCb Callback specifying inner steps.
---@param n? integer Maximum inner passes; defaults to 1000.
---@return Algorithm inner
function Builder:inner(cb, n)
	local inner = Alg.new()
	inner.op = "loop"
	inner.max_iters = n or 1000

	cb(Builder.new(inner.steps))

	self.steps[#self.steps + 1] = { op = "inner", alg = inner }
	self.last = self.steps[#self.steps]
	return inner
end

--- Apply the explicit correction for a field (e.g. velocity after pressure solve).
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:correct(field)
	field = fname(field)
	V.identifier(field, "alg:correct")
	return push(self, { op = "correct", field = field })
end

--- Zero a field.
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:zero(field)
	field = fname(field)
	V.identifier(field, "alg:zero")
	return push(self, { op = "zero", field = field })
end

--- Attach a label to the most recently appended step for use in listings.
---@param str string Step label.
---@return AlgBuilder self
function Builder:tag(str)
	assert(self.last, "alg:tag: no step to tag")
	self.last.tag = str
	return self
end

--
-- Algorithm constructor
--

function Physics:algorithm(fn)
	local builder = Builder.new()
end

return Physics
