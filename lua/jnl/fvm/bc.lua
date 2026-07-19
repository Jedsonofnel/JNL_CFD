-- jnl/fvm/bc.lua - BC descriptor constructors and set builder
-- <jed@nelson.ac> // 2026-07-19

local V = require("jnl.core.validation")

--- Normal BC kind constant for use with BC.nt().
local N = 0
--- Dirichlet BC kind constant for use with BC.nt().
local D = 1
--- Robin BC kind constant for use with BC.nt().
local R = 2

---@class BCDescriptor
---@field kind string BC kind tag recognised by the FVM dispatcher.
---@field rank integer Tensor rank: 0 = scalar, 1 = vector.

--
-- Scalar primitives
--

---@param value number Prescribed value.
---@return BCDescriptor
local function dirichlet(value)
    V.typeof(value, "number", "BC.dirichlet: value")
    return { kind = "dirichlet_s", rank = 0, value = value }
end

---@param grad_n? number Normal gradient; defaults to zero.
---@return BCDescriptor
local function neumann(grad_n)
    grad_n = grad_n or 0.0
    V.typeof(grad_n, "number", "BC.neumann: grad_n")
    return { kind = "neumann_s", rank = 0, grad_n = grad_n }
end

---@param a number Coefficient on phi.
---@param b number Coefficient on dphi/dn.
---@param c number Right-hand side value.
---@return BCDescriptor
local function robin(a, b, c)
    V.typeof(a, "number", "BC.robin: a")
    V.typeof(b, "number", "BC.robin: b")
    V.typeof(c, "number", "BC.robin: c")
    return { kind = "robin_s", rank = 0, a = a, b = b, c = c }
end

--
-- Vector primitives
--

---@param ux number x-component value.
---@param uy number y-component value.
---@return BCDescriptor
local function dirichlet_v(ux, uy)
    V.typeof(ux, "number", "BC.dirichlet_v: ux")
    V.typeof(uy, "number", "BC.dirichlet_v: uy")
    return { kind = "dirichlet_v", rank = 1, ux = ux, uy = uy }
end

---@param ux_gn? number x-gradient; defaults to zero.
---@param uy_gn? number y-gradient; defaults to zero.
---@return BCDescriptor
local function neumann_v(ux_gn, uy_gn)
    ux_gn = ux_gn or 0.0
    uy_gn = uy_gn or 0.0
    V.typeof(ux_gn, "number", "BC.neumann_v: ux_gn")
    V.typeof(uy_gn, "number", "BC.neumann_v: uy_gn")
    return { kind = "neumann_v", rank = 1, ux_gn = ux_gn, uy_gn = uy_gn }
end

---@param nkind integer Normal component kind (BC.N | BC.D | BC.R).
---@param nval number Normal component value.
---@param tkind integer Tangential component kind (BC.N | BC.D | BC.R).
---@param tval number Tangential component value.
---@return BCDescriptor
local function nt(nkind, nval, tkind, tval)
    V.typeof(nval, "number", "BC.nt: nval")
    V.typeof(tval, "number", "BC.nt: tval")
    return {
        kind = "nt_v",
        rank = 1,
        nkind = nkind,
        nval = nval,
        tkind = tkind,
        tval = tval,
    }
end

--
-- Scalar helpers
--

---@param value number Prescribed value.
---@return BCDescriptor
local function fixed(value)
    return dirichlet(value)
end

---@return BCDescriptor
local function nograd()
    return neumann(0.0)
end

---@param value? number Reference pressure; defaults to zero.
---@return BCDescriptor
local function pressure_outlet(value)
    return dirichlet(value or 0.0)
end

--
-- Vector helpers
--

---@return BCDescriptor
local function no_slip()
    return dirichlet_v(0.0, 0.0)
end

---@return BCDescriptor
local function free_slip()
    return nt(D, 0.0, N, 0.0)
end

---@param ux number x-component of inlet velocity.
---@param uy number y-component of inlet velocity.
---@return BCDescriptor
local function inlet(ux, uy)
    V.typeof(ux, "number", "BC.inlet: ux")
    V.typeof(uy, "number", "BC.inlet: uy")
    return dirichlet_v(ux, uy)
end

---@return BCDescriptor
local function outlet()
    return neumann_v(0.0, 0.0)
end

---@param ux number Wall x-velocity.
---@param uy? number Wall y-velocity; defaults to zero.
---@return BCDescriptor
local function moving_wall(ux, uy)
    uy = uy or 0.0
    V.typeof(ux, "number", "BC.moving_wall: ux")
    V.typeof(uy, "number", "BC.moving_wall: uy")
    return dirichlet_v(ux, uy)
end

--
-- Set
--

--- A patch entry accumulated by FieldSpec:on() or FieldSpec:rest().
---@class BCEntry: BCDescriptor
---@field patch string|true Patch name, or true for the :rest() catch-all entry.

---@class BCFieldSpec
---@field name string Field name.
---@field rank integer Tensor rank: 0 = scalar, 1 = vector.
---@field list BCEntry[]
local FieldSpec = {}
FieldSpec.__index = FieldSpec

---@param spec BCDescriptor
---@param field_rank integer
---@param ctx string
local function check_rank(spec, field_rank, ctx)
    if spec.rank ~= field_rank then
        error(
            ("%s: descriptor rank %d does not match field rank %d"):format(
                ctx,
                spec.rank,
                field_rank
            ),
            2
        )
    end
end

---@param patch string Patch name.
---@param spec BCDescriptor
---@return BCFieldSpec self
function FieldSpec:on(patch, spec)
    V.typeof(patch, "string", "FieldSpec:on: patch")
    V.typeof(spec, "table", "FieldSpec:on: spec")
    check_rank(
        spec,
        self.rank,
        ("FieldSpec:on [field '%s', patch '%s']"):format(self.name, patch)
    )
    local entry = { patch = patch }
    for k, v in pairs(spec) do
        entry[k] = v
    end
    self.list[#self.list + 1] = entry
    return self
end

--- Apply a BC to all patches not explicitly covered by :on().
---@param spec BCDescriptor
---@return BCFieldSpec self
function FieldSpec:rest(spec)
    V.typeof(spec, "table", "FieldSpec:rest: spec")
    check_rank(
        spec,
        self.rank,
        ("FieldSpec:rest [field '%s']"):format(self.name)
    )
    local entry = { patch = true }
    for k, v in pairs(spec) do
        entry[k] = v
    end
    self.list[#self.list + 1] = entry
    return self
end

---@class BCSet
---@field fields table<string, BCFieldSpec>
local Set = {}
Set.__index = Set

---@return BCSet
function Set.new()
    return setmetatable({ fields = {} }, Set)
end

---@param set BCSet
---@param name string
---@param rank integer
---@return BCFieldSpec
local function add_field(set, name, rank)
    V.typeof(name, "string", "BCSet: field name")
    if set.fields[name] then
        error(("BCSet: field '%s' already declared"):format(name), 3)
    end
    local fs = setmetatable({ name = name, rank = rank, list = {} }, FieldSpec)
    set.fields[name] = fs
    return fs
end

---@param name string Field name matching the solver registry.
---@return BCFieldSpec
function Set:scalar(name)
    return add_field(self, name, 0)
end

---@param name string Field name matching the solver registry.
---@return BCFieldSpec
function Set:vector(name)
    return add_field(self, name, 1)
end

--- Validate the set against a mesh. Errors on unknown patches; warns on uncovered or duplicate patches.
---@param mesh Mesh2D
function Set:validate(mesh)
    local warnings = {}
    local errors = {}

    local mesh_patches = {}
    for _, p in ipairs(mesh:patches()) do
        mesh_patches[p.name] = true
    end

    for fname, fs in pairs(self.fields) do
        local covered = {}
        local has_rest = false

        for _, entry in ipairs(fs.list) do
            if entry.patch == true then
                has_rest = true
            elseif not mesh_patches[entry.patch] then
                errors[#errors + 1] = ("field '%s': patch '%s' does not exist on mesh"):format(
                    fname,
                    entry.patch
                )
            else
                if covered[entry.patch] then
                    warnings[#warnings + 1] = ("field '%s': patch '%s' assigned more than once"):format(
                        fname,
                        entry.patch
                    )
                end
                covered[entry.patch] = true
            end
        end

        if not has_rest then
            for pname in pairs(mesh_patches) do
                if not covered[pname] then
                    warnings[#warnings + 1] = ("field '%s': patch '%s' has no BC (implicit nograd)"):format(
                        fname,
                        pname
                    )
                end
            end
        end
    end

    return warnings, errors
end

---@return BCSet
local function new_set()
    return Set.new()
end

return {
    -- kind enum
    N = N,
    D = D,
    R = R,
    NEUMANN = N,
    DIRICHLET = D,
    ROBIN = R,
    -- scalar constructors
    dirichlet = dirichlet,
    fixed = fixed,
    pressure_outlet = pressure_outlet,
    neumann = neumann,
    nograd = nograd,
    robin = robin,
    -- vector constructors
    dirichlet_v = dirichlet_v,
    no_slip = no_slip,
    wall = no_slip,
    inlet = inlet,
    moving_wall = moving_wall,
    neumann_v = neumann_v,
    outlet = outlet,
    nt = nt,
    free_slip = free_slip,
    slip = free_slip,
    symmetry = free_slip,
    -- set
    new_set = new_set,
}
