-- jnl/fvm.lua - FVM constructors for jnl physics description layer
-- <jed@nelson.ac> // 2026-05-08

local fvm = {}

-- expression constructor/validator
local function expr(v)
	if type(v) == "number" then
		return { kind = "const", value = v }
	elseif type(v) == "string" then
		assert(not v:match("^__"),
			"symbol names starting with '__' are reserved: " .. v)
		return { kind = "sym", name = v }
	elseif type(v) == "table" and type(v.kind) == "string" then
		return v
	else
		error("expected expression (number, string symbol, or E table), got: "
			.. tostring(v), 3)
	end
end

fvm.FVM_KINDS = {
	div = true,
	lap = true,
	dt = true,
	grad = true,
	su = true,
	sp = true,
}

--
-- Expression system for cellwise arithmetic
--

local E = {}
fvm.E = E

-- Atoms

function E.sym(name)
	assert(type(name) == "string",
		"E:sym: expected string, got " .. type(name))
	assert(not name:match("^__"),
		"E:sym: names starting with '__' are reserved: " .. name)
	return { kind = "sym", name = name }
end

function E.const(v)
	assert(type(v) == "number",
		"E:const: expected number, got " .. type(v))
	return { kind = "const", value = v }
end

-- Arithmetic

function E.add(a, b)
	return { kind = "add", expr(a), expr(b) }
end

function E.sub(a, b)
	return { kind = "sub", expr(a), expr(b) }
end

function E.mul(a, b)
	return { kind = "mul", expr(a), expr(b) }
end

function E.div(a, b)
	return { kind = "div", expr(a), expr(b) }
end

function E.neg(a)
	return { kind = "neg", value = expr(a) }
end

function E.pow(base, exp)
	return { kind = "pow", base = expr(base), exp = expr(exp) }
end

-- System access - reads from state

function E.cellvol()
	return { kind = "cellvol" }
end

function E.diag(field_name, i)
	assert(type(field_name) == "string",
		"E:diag: expected field name string")
	assert(i == nil or i == "x" or i == "y",
		"E:diag: component (i) must be nil or 'x' or 'y'")
	return { kind = "diag", field = field_name, component = i }
end

-- Flux specification

function E.mwi(U_name, p_name)
	assert(type(U_name) == "string",
		"E:mwi: U must be a field name string")
	assert(type(p_name) == "string",
		"E:mwi: p must be a field name string")
	return { kind = "mwi", U = U_name, p = p_name }
end

-- Bespoke physics

function E.strain_rate_sq(U_name)
	assert(type(U_name) == "string",
		"E:strain_rate_sq: U must be a field name string")
	return { kind = "strain_rate_sq", U = U_name }
end

--
-- FVM: Differential operators etc
--

local FVM = {}
fvm.FVM = FVM

function FVM.dt(rho, phi)
end

function FVM.div(flux, phi, scheme)
end

function FVM.lap(gamma, phi)
end

-- should this be a cellwise expression instead?? (or as well?)  think so
-- then if it's included in an eq it implicitly gets wrapped in an Su?
function FVM.grad(phi, component)
end

function FVM.su(expr)
end

function FVM.sp(expr)
end

--
-- Registry: Putting it all together
--

-- TODO: implement this with structural checking

local Reg = {}
Reg.__index = Reg

function Reg:constant(sym, value)
end

function Reg:region_property(sym, spec)
end

function Reg:derived(sym, spec)
end

function Reg:field(sym, spec)
end

function Reg:vector(sym, spec)
end

function Reg.new(self)
	return setmetatable({}, self)
end

--
-- Algorithm
--

local Alg = {}
Alg.__index = Alg

-- passed into callback function for Alg
local alg_target = {}

function alg_target:solve(name)
	assert(type(name) == "string",
		"target:solve: expects field name")
	return { kind = "solve", name = "name" }
end

function alg_target:clip(name)
	assert(type(name) == "string",
		"target:clip: expects field name")
	return { kind = "clip", name = "name" }
end

function alg_target:hook(fn)
	assert(type(fn) == "function",
		"target:hook: expects callback function")
	return { kind = "hook", fn = fn }
end

function alg_target:inner(cb)
	assert(type(cb) == "function",
		"target:inner: expects callback function")
	return { kind = "inner", cb = cb }
end

function Alg:outer(cb)
	local spec = cb(alg_target)

	-- TODO: some validation on spec maybe?
	-- should be an array of steps
	assert(type(spec) == "table",
		"Alg:outer: expect callback to return a table")

	self.spec = spec
end

function Alg.new(self)
	return setmetatable({}, self)
end

return fvm
