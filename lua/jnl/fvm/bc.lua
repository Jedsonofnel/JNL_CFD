-- jnl/fvm/bc.lua - BC descriptor constructors

local BC = {}

-- Kind constants matching C enum jnl_bc_kind, re-exported for nt() callers
BC.N = 0
BC.D = 1
BC.R = 2

--
-- Scalar primitives
--

function BC.dirichlet(value)
	assert(type(value) == "number", "BC.dirichlet: value must be a number")
	return { kind = "dirichlet_s", value = value }
end

-- grad_n defaults to zero (zero-flux)
function BC.neumann(grad_n)
	grad_n = grad_n or 0.0
	assert(type(grad_n) == "number", "BC.neumann: grad_n must be a number")
	return { kind = "neumann_s", grad_n = grad_n }
end

-- general Robin: a*phi + b*(dphi/dn) = c
function BC.robin(a, b, c)
	assert(type(a) == "number" and type(b) == "number" and type(c) == "number",
		"BC.robin: a, b, c must be numbers")
	return { kind = "robin_s", a = a, b = b, c = c }
end

--
-- Vector primitives
--

function BC.dirichlet_v(ux, uy)
	assert(type(ux) == "number" and type(uy) == "number",
		"BC.dirichlet_v: ux and uy must be numbers")
	return { kind = "dirichlet_v", ux = ux, uy = uy }
end

-- zero-gradient vector by default
function BC.neumann_v(ux_gn, uy_gn)
	ux_gn = ux_gn or 0.0
	uy_gn = uy_gn or 0.0
	assert(type(ux_gn) == "number" and type(uy_gn) == "number",
		"BC.neumann_v: ux_gn and uy_gn must be numbers")
	return { kind = "neumann_v", ux_gn = ux_gn, uy_gn = uy_gn }
end

-- normal/tangential split — use BC.N / BC.D / BC.R for kind args
function BC.nt(nkind, nval, tkind, tval)
	assert(type(nval) == "number" and type(tval) == "number",
		"BC.nt: nval and tval must be numbers")
	return { kind = "nt_v", nkind = nkind, nval = nval, tkind = tkind, tval = tval }
end

--
-- Scalar helpers
--

-- alias: intent is clearer than raw dirichlet at a fixed wall temperature etc.
function BC.fixed(value)
	return BC.dirichlet(value)
end

-- zero normal gradient — the most common outlet/symmetry scalar condition
function BC.nograd()
	return BC.neumann(0.0)
end

-- pressure outlet at a specified reference value
function BC.pressure_outlet(value)
	return BC.dirichlet(value or 0.0)
end

--
-- Vector helpers
--

-- no-slip viscous wall
function BC.no_slip()
	return BC.dirichlet_v(0.0, 0.0)
end

-- alias
BC.wall = BC.no_slip

-- free-slip / symmetry plane: zero normal velocity, zero tangential gradient
function BC.free_slip()
	return BC.nt(BC.D, 0.0, BC.N, 0.0)
end

-- alias: same condition, different physical intent name
BC.slip     = BC.free_slip
BC.symmetry = BC.free_slip

-- prescribed inlet velocity
function BC.inlet(ux, uy)
	assert(type(ux) == "number" and type(uy) == "number",
		"BC.inlet: ux and uy must be numbers")
	return BC.dirichlet_v(ux, uy)
end

-- advective / zero-gradient outlet
function BC.outlet()
	return BC.neumann_v(0.0, 0.0)
end

-- moving wall (e.g. Couette lid)
function BC.moving_wall(ux, uy)
	uy = uy or 0.0
	assert(type(ux) == "number" and type(uy) == "number",
		"BC.moving_wall: ux and uy must be numbers")
	return BC.dirichlet_v(ux, uy)
end

--
-- BC Set
--

local Set = {}
Set.__index = Set

local FieldSpec = {}
FieldSpec.__index = FieldSpec

--
-- FieldSpec
--

local function new_field_spec(parent_set, name, rank)
	local fs = setmetatable({
		parent = parent_set,
		name   = name,
		rank   = rank,
		list   = {},
	}, FieldSpec)
	parent_set.fields[name] = fs
	return fs
end

function FieldSpec:on(patch, spec)
	assert(type(patch) == "string", "Set:on: patch must be a string")
	assert(type(spec) == "table", "Set:on: spec must be a BC descriptor table")
	local bc = { patch = patch }
	for k, v in pairs(spec) do bc[k] = v end
	self.list[#self.list + 1] = bc
	return self
end

-- delegation back to parent for continued chaining
function FieldSpec:scalar(name) return self.parent:scalar(name) end

function FieldSpec:vector(name) return self.parent:vector(name) end

function FieldSpec:default(spec) return self.parent:default(spec) end

function FieldSpec:build() return self.parent:build() end

--
-- Set
--

function Set.new()
	return setmetatable({
		fields   = {},
		order    = {},
		fallback = nil,
	}, Set)
end

function Set:scalar(name)
	assert(type(name) == "string", "Set:scalar: name must be a string")
	self.order[#self.order + 1] = name
	return new_field_spec(self, name, 0)
end

function Set:vector(name)
	assert(type(name) == "string", "Set:vector: name must be a string")
	self.order[#self.order + 1] = name
	return new_field_spec(self, name, 1)
end

function Set:default(spec)
	assert(type(spec) == "table", "Set:default: spec must be a BC descriptor table")
	self.fallback = spec
	return self
end

function Set:build()
	local out   = {}
	local ranks = {}
	for _, name in ipairs(self.order) do
		local fs    = self.fields[name]
		out[name]   = fs.list
		ranks[name] = fs.rank
	end
	return { fields = out, ranks = ranks, default = self.fallback }
end

Set.__call = function(self) return self:build() end

function BC.new_set()
	return Set.new()
end

return BC
