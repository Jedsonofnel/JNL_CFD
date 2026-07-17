-- jnl/fvm/bc.lua - BC descriptor constructors
-- <jed@nelson.ac> // 2026-06-10

--- Construct boundary condition descriptors for FVM cases.
---
--- There are two usage patterns:
---
--- Direct descriptors — build a plain table per field and attach patch names manually:
---
---     bcs = {
---         p = { { patch = "east", bc.pressure_outlet(0.0) } },
---     }
---
--- Set builder (recommended) — fluent API that enforces field names and patch strings:
---
---     bcs = bc.new_set()
---         :vector("U")
---             :on("south", bc.no_slip())
---             :on("north", bc.moving_wall(1.0, 0.0))
---         :scalar("p")
---             :on("east",  bc.pressure_outlet(0.0))
---             :on("south", bc.nograd())
---         :build()
---
--- Both forms are accepted by Case.new().
local BC = {}

--- Normal BC kind constant for use with BC.nt().
BC.N = 0
--- Dirichlet BC kind constant for use with BC.nt().
BC.D = 1
--- Robin BC kind constant for use with BC.nt().
BC.R = 2

--- A boundary condition descriptor table.
--- Returned by all BC constructor functions and accepted by FieldSpec:on().
---@class BCDescriptor
---@field kind string BC kind tag recognised by the FVM dispatcher.

--
-- Scalar primitives
--

--- Prescribe a fixed scalar value on a boundary face.
---@param value number Prescribed value.
---@return BCDescriptor
function BC.dirichlet(value)
    assert(type(value) == "number", "BC.dirichlet: value must be a number")
    return { kind = "dirichlet_s", value = value }
end

--- Prescribe the normal gradient of a scalar field on a boundary face.
---@param grad_n? number Normal gradient; defaults to zero (zero-flux).
---@return BCDescriptor
function BC.neumann(grad_n)
    grad_n = grad_n or 0.0
    assert(type(grad_n) == "number", "BC.neumann: grad_n must be a number")
    return { kind = "neumann_s", grad_n = grad_n }
end

--- General Robin condition: a*phi + b*(dphi/dn) = c.
---@param a number Coefficient on phi.
---@param b number Coefficient on dphi/dn.
---@param c number Right-hand side value.
---@return BCDescriptor
function BC.robin(a, b, c)
    assert(
        type(a) == "number" and type(b) == "number" and type(c) == "number",
        "BC.robin: a, b, c must be numbers"
    )
    return { kind = "robin_s", a = a, b = b, c = c }
end

--
-- Vector primitives
--

--- Prescribe fixed x and y velocity components on a boundary face.
---@param ux number x-component value.
---@param uy number y-component value.
---@return BCDescriptor
function BC.dirichlet_v(ux, uy)
    assert(
        type(ux) == "number" and type(uy) == "number",
        "BC.dirichlet_v: ux and uy must be numbers"
    )
    return { kind = "dirichlet_v", ux = ux, uy = uy }
end

--- Prescribe the normal gradients of both velocity components.
---@param ux_gn? number x-gradient; defaults to zero.
---@param uy_gn? number y-gradient; defaults to zero.
---@return BCDescriptor
function BC.neumann_v(ux_gn, uy_gn)
    ux_gn = ux_gn or 0.0
    uy_gn = uy_gn or 0.0
    assert(
        type(ux_gn) == "number" and type(uy_gn) == "number",
        "BC.neumann_v: ux_gn and uy_gn must be numbers"
    )
    return { kind = "neumann_v", ux_gn = ux_gn, uy_gn = uy_gn }
end

--- Normal/tangential split condition for a vector field.
---
--- Use BC.N / BC.D / BC.R for the kind arguments.
---@param nkind integer Normal component kind (BC.N | BC.D | BC.R).
---@param nval number   Normal component value.
---@param tkind integer Tangential component kind (BC.N | BC.D | BC.R).
---@param tval number   Tangential component value.
---@return BCDescriptor
function BC.nt(nkind, nval, tkind, tval)
    assert(
        type(nval) == "number" and type(tval) == "number",
        "BC.nt: nval and tval must be numbers"
    )
    return {
        kind = "nt_v",
        nkind = nkind,
        nval = nval,
        tkind = tkind,
        tval = tval,
    }
end

--
-- Scalar helpers
--

--- Alias for BC.dirichlet. Clearer intent for fixed temperature or concentration.
---@param value number Prescribed value.
---@return BCDescriptor
function BC.fixed(value)
    return BC.dirichlet(value)
end

--- Zero normal gradient. The most common outlet or symmetry scalar condition.
---@return BCDescriptor
function BC.nograd()
    return BC.neumann(0.0)
end

--- Fix the pressure at a boundary face.
---@param value? number Reference pressure; defaults to zero.
---@return BCDescriptor
function BC.pressure_outlet(value)
    return BC.dirichlet(value or 0.0)
end

--
-- Vector helpers
--

--- No-slip viscous wall: zero velocity in both components.
---@return BCDescriptor
function BC.no_slip()
    return BC.dirichlet_v(0.0, 0.0)
end

--- Alias for no_slip.
BC.wall = BC.no_slip

--- Free-slip or symmetry plane: zero normal velocity, zero tangential gradient.
---@return BCDescriptor
function BC.free_slip()
    return BC.nt(BC.D, 0.0, BC.N, 0.0)
end

--- Alias for free_slip.
BC.slip = BC.free_slip
--- Alias for free_slip.
BC.symmetry = BC.free_slip

--- Prescribed inlet velocity.
---@param ux number x-component of inlet velocity.
---@param uy number y-component of inlet velocity.
---@return BCDescriptor
function BC.inlet(ux, uy)
    assert(
        type(ux) == "number" and type(uy) == "number",
        "BC.inlet: ux and uy must be numbers"
    )
    return BC.dirichlet_v(ux, uy)
end

--- Zero-gradient advective outlet.
---@return BCDescriptor
function BC.outlet()
    return BC.neumann_v(0.0, 0.0)
end

--- Moving wall, e.g. the lid in Couette or lid-driven cavity flow.
---@param ux number Wall x-velocity.
---@param uy? number Wall y-velocity; defaults to zero.
---@return BCDescriptor
function BC.moving_wall(ux, uy)
    uy = uy or 0.0
    assert(
        type(ux) == "number" and type(uy) == "number",
        "BC.moving_wall: ux and uy must be numbers"
    )
    return BC.dirichlet_v(ux, uy)
end

--
-- Set builder
--

--- A single-field specification within a BCSetBuilder.
---
--- Returned by BCSetBuilder:scalar() and BCSetBuilder:vector(). Methods on
--- BCFieldSpec delegate back to the parent builder, so chaining can move
--- freely between fields without breaking the fluent call chain.
---@class BCFieldSpec
---@field parent BCSetBuilder
---@field name string Field name.
---@field rank integer Tensor rank: 0 = scalar, 1 = vector.
---@field list BCEntry[] Patch entries accumulated by :on().
local FieldSpec = {}
FieldSpec.__index = FieldSpec

--- A patch entry in a built BC table.
---@class BCEntry: BCDescriptor
---@field patch string Patch name this entry applies to.

--- Built BC table accepted by Case.new().
---@class BCSet
---@field fields table<string, BCEntry[]> Per-field patch lists.
---@field ranks table<string, integer>    Tensor rank of each declared field.
---@field default BCDescriptor?           Fallback descriptor for unspecified patches.

---@private
local function new_field_spec(parent_set, name, rank)
    local fs = setmetatable({
        parent = parent_set,
        name = name,
        rank = rank,
        list = {},
    }, FieldSpec)
    parent_set.fields[name] = fs
    return fs
end

--- Add a patch BC to this field.
---@param patch string Patch name.
---@param spec BCDescriptor BC descriptor returned by a BC constructor.
---@return BCFieldSpec self
function FieldSpec:on(patch, spec)
    assert(type(patch) == "string", "Set:on: patch must be a string")
    assert(type(spec) == "table", "Set:on: spec must be a BC descriptor table")
    local entry = { patch = patch }
    for k, v in pairs(spec) do
        entry[k] = v
    end
    self.list[#self.list + 1] = entry
    return self
end

-- Delegation methods: allow continued chaining on the parent builder
-- without requiring the caller to break out of the fluent expression.

---@return BCFieldSpec
function FieldSpec:scalar(name)
    return self.parent:scalar(name)
end

---@return BCFieldSpec
function FieldSpec:vector(name)
    return self.parent:vector(name)
end

---@return BCSetBuilder
function FieldSpec:default(spec)
    return self.parent:default(spec)
end

---@return BCSet
function FieldSpec:build()
    return self.parent:build()
end

-- In FieldSpec:

--- Apply a BC descriptor to all patches not already covered by an :on() call.
---@param spec BCDescriptor BC descriptor.
---@return BCFieldSpec self
function FieldSpec:all(spec)
    assert(
        type(spec) == "table",
        "FieldSpec:all: spec must be a BC descriptor table"
    )
    local entry = { patch = true }
    for k, v in pairs(spec) do
        entry[k] = v
    end
    self.list[#self.list + 1] = entry
    return self
end

--
-- BCSetBuilder
--

--- Fluent builder for assembling a complete BC table.
---@class BCSetBuilder
---@field fields table<string, BCFieldSpec>
---@field order string[]
---@field fallback BCDescriptor?
local Set = {}
Set.__index = Set

--- Create a new BCSetBuilder.
---@return BCSetBuilder
function Set.new()
    return setmetatable({
        fields = {},
        order = {},
        fallback = nil,
    }, Set)
end

--- Declare a scalar field and return its field spec for patch assignment.
---@param name string Field name matching the registry declaration.
---@return BCFieldSpec
function Set:scalar(name)
    assert(type(name) == "string", "Set:scalar: name must be a string")
    self.order[#self.order + 1] = name
    return new_field_spec(self, name, 0)
end

--- Declare a vector field and return its field spec for patch assignment.
---@param name string Field name matching the registry declaration.
---@return BCFieldSpec
function Set:vector(name)
    assert(type(name) == "string", "Set:vector: name must be a string")
    self.order[#self.order + 1] = name
    return new_field_spec(self, name, 1)
end

--- Set a fallback descriptor applied to patches not covered by any :on() call.
---@param spec BCDescriptor Fallback BC descriptor.
---@return BCSetBuilder self
function Set:default(spec)
    assert(
        type(spec) == "table",
        "Set:default: spec must be a BC descriptor table"
    )
    self.fallback = spec
    return self
end

--- Apply a fallback BC to all otherwise-uncovered patches on the most recently
--- declared field.
---@param spec BCDescriptor BC descriptor.
---@return BCSetBuilder self
function Set:all(spec)
    assert(type(spec) == "table", "Set:all: spec must be a BC descriptor table")
    local last = self.order[#self.order]
    assert(last, "Set:all: no field declared yet")
    self.fields[last]:all(spec)
    return self
end

--- Build and return the finished BC table.
---@return BCSet
function Set:build()
    local out = {}
    local ranks = {}
    for _, name in ipairs(self.order) do
        local fs = self.fields[name]
        out[name] = fs.list
        ranks[name] = fs.rank
    end
    return { fields = out, ranks = ranks, default = self.fallback }
end

Set.__call = function(self)
    return self:build()
end

--- Create a fluent BC set builder.
---
--- Typical usage:
---
---     local bcs = bc.new_set()
---         :vector("U")
---             :on(E.PATCH.SOUTH, bc.no_slip())
---             :on(E.PATCH.NORTH, bc.moving_wall(1.0, 0.0))
---         :scalar("p")
---             :on(E.PATCH.EAST, bc.pressure_outlet(0.0))
---             :on(E.PATCH.WEST, bc.nograd())
---         :build()
---
---@return BCSetBuilder
function BC.new_set()
    return Set.new()
end

return BC
