-- jnl/fvm/instruction.lua

-- deps
local V = require("jnl.core.validation")

local Inst = {}
Inst.__index = Inst

local function new(op, fields)
	return setmetatable({ op = op, fields = fields or {} }, Inst)
end

function Inst.new(op, fields)
	return new(op, fields)
end

function Inst:__index(k)
	if Inst[k] then return Inst[k] end
	return self.fields[k]
end

function Inst:__newindex(k)
	self.fields[k] = k
end

--
-- Constructors: abstract instructions (high level)
--

function Inst.fill(field, value)
	V.identifier(field, "Inst.fill field")
	V.typeof(value, "number", "Inst.fill value")
	return new("fill", { field = field, value = value, level = "abstract" })
end

function Inst.evaluate(field)
	V.identifier(field, "Inst.evaluate field")
	return new("evaluate", { field = field, implicit = true, level = "abstract" })
end

function Inst.solve(field)
	V.identifier(field, "Inst.solve field")
	return new("solve", { field = field, level = "abstract" })
end

function Inst.correct(field)
	V.identifier(field, "Inst.correct field")
	return new("correct", { field = field, level = "abstract" })
end

function Inst.clip(field, lo, hi)
	hi = hi or math.huge
	V.identifier(field, "Inst.clip field")
	return new("clip", { field = field, lo = lo, hi = hi, level = "abstract" })
end

function Inst.zero(field)
	V.identifier(field, "Inst.zero field")
	return new("zero", { field = field, level = "abstract" })
end

--
-- Constructors: explicit evaluation instructions
--

function Inst.eval_expr(field, node)
	V.identifier(field, "Inst.eval_expr field")
	return new("eval_expr", { field = field, node = node })
end

-- anonymous evaluation of coeff into a scratch
function Inst.eval_coeff(node)
	return new("eval_coeff", { node = node })
end

-- requires field to be rank 1 or 2?
function Inst.divergence(field)
	return new("divergence", { field = field })
end

--
-- Constructors: linear algebra assembly instructions
--

function Inst.sys_reset(field)
	V.identifier(field, "Inst.sys_reset field")
	return new("sys_reset", { field = field })
end

---@param field string
---@param coeff Node
function Inst.laplacian_sys(field, coeff)
	V.identifier(field, "Inst.laplacian_sys field")
	return new("laplacian_sys", { field = field, coeff = coeff })
end

---@param field string
---@param coeff Node
function Inst.divergence_sys(field, coeff)
	V.identifier(field, "Inst.divergence_sys field")
	return new("divergence_sys", { field = field, coeff = coeff })
end

---@param field string
---@param expr Node
function Inst.su(field, expr)
	V.identifier(field, "Inst.su field")
	return new("su", { field = field, node = expr })
end

---@param field string
---@param expr Node
function Inst.sp(field, expr)
	V.identifier(field, "Inst.sp field")
	return new("sp", { field = field, node = expr })
end

-- diag_snapshot
-- apply_correction
-- apply_bc_patch

function Inst.solve_linalg(field)
	V.identifier(field, "Inst.solve_linalg field")
	return new("solve_linalg", { field = field })
end

--
-- Display
--

-- TODO need access to algorithm config as well!
function Inst:__tostring(indent)
	indent = indent or "  "

	return indent .. "?" .. self.op
end
