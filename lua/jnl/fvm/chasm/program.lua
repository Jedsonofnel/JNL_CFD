-- jnl/fvm/chasm/program.lua
-- <jed@nelson.ac> // 2026-07-18

-- deps
local V = require("jnl.core.validation")
local Vec = require("jnl.core.vec")
local Pool = require("jnl.core.scratch_pool")
local B = require("jnl.fvm.bindings")
local VM = require("jnl.fvm.chasm.vm")

--
-- Vars
--

---@class CHASMvar
---@field name string
---@field rank integer
---@field has_sys boolean
---@field fvsys FvSys?
---@field facewise boolean
---@field vec Vec?
---@field domain_name string
---@field init number?|table?
---@field x? CHASMvar x component if root has rank > 0
---@field y? CHASMvar y component if root has rank > 0
local Var = {}
Var.__index = Var

function Var:__tostring()
    return self.name
end

---@param domain CHASMdomain
---@param name string
---@param init number?
---@return CHASMvar
local function new_scalar(domain, name, init)
    init = init or 0.0

    ---@type CHASMvar
    local var = setmetatable({
        domain_name = domain.name,
        name = name,
        rank = 0,
        has_sys = false,
        init = init,
    }, Var)
    return var
end

---@param domain CHASMdomain
---@param name string
---@param init number|number[]?
---@return CHASMvar
local function new_vector(domain, name, init)
    init = init or { 0, 0 }

    local init_tbl = { 0, 0 }
    if type(init) == "number" then
        init_tbl = { init, init }
    elseif type(init) == "table" and #init == 2 then
        init_tbl = { init[1], init[2] }
    else
        error("CHASM:vector init: expected number or table with format {x, y}")
    end

    -- TODO use official mangling channels
    local x = new_scalar(domain, "(" .. name .. "_x)", init_tbl[1])
    local y = new_scalar(domain, "(" .. name .. "_y)", init_tbl[2])

    ---@type CHASMvar
    local var = setmetatable({
        domain_name = domain.name,
        name = name,
        rank = 1,
        has_sys = false,
        facewise = false,
        init = init_tbl,
        x = x,
        y = y,
    }, Var)

    return var
end

function Var:sys()
    self.has_sys = true
    return self
end

function Var:face()
    self.facewise = true
    return self
end

function Var:residual_lt(v)
    return { kind = "lt", src = "residual", key = self.name, val = v }
end

function Var:residual_gt(v)
    return { kind = "gt", src = "residual", key = self.name, val = v }
end

-- TODO add norm and delta predicates too

--
-- Constants - like vars but constant and not scoped to domain
--

---@class CHASMconst
---@field value number
---@field name string
local Const = {}
Const.__index = Const

function Const:__tostring()
    return string.format("%s<%g>", self.name, self.value)
end

---@param name string
---@param value number
---@return CHASMconst
local function new_constant(name, value)
    return setmetatable({
        name = name,
        value = value,
    }, Const)
end

--
-- Domains
--

---@class CHASMdomain
---@field prog CHASMprogram
---@field name string
---@field mesh Mesh2D
local Domain = {}
Domain.__index = Domain

---@param program CHASMprogram
---@param name string
---@return CHASMdomain
local function new_domain(program, name)
    return setmetatable({
        prog = program,
        name = name,
        vars = {},
    }, Domain)
end

---@param name string
---@param init number?
---@return CHASMvar
function Domain:scalar(name, init)
    V.identifier(name, "CHASM:scalar(name)")
    local var = new_scalar(self, name, init)
    if self.prog.vars[name] then
        error(string.format("var '%s' already exists", name), 2)
    end
    self.prog.vars[name] = var
    return var
end

---@param name string
---@param init number|number[]?
---@return CHASMvar
function Domain:vector(name, init)
    V.identifier(name, "CHASM new_vector name")
    local var = new_vector(self, name, init)
    if self.prog.vars[name] then
        error(string.format("var '%s' already exists", name), 2)
    end
    self.prog.vars[name] = var
    self.prog.vars[var.x.name] = var.x
    self.prog.vars[var.y.name] = var.y
    return var
end

---@param mesh Mesh2D
---@param bcs BCSet
function Domain:bind(mesh, bcs)
    assert(mesh, "mesh required for binding")
    assert(bcs, "bcs required for binding")
    local warnings, errors = bcs:validate(mesh)
    if #errors > 0 then
        error(string.format("BC errors:\n%s", table.concat(errors, "\n  ")))
    end
    if #warnings > 0 then
        print(string.format("BC warnings:\n%s", table.concat(warnings, "\n  ")))
    end

    self.mesh = mesh
    self.bcs = bcs

    -- TODO validate BCS are defined for every field

    self.lengths = {
        cell = mesh:n_cells(),
        face = mesh:n_faces(),
    }
    self.pools = {
        cell = Pool.new(self.lengths.cell),
        face = Pool.new(self.lengths.face),
    }

    return self
end

function Domain:allocate_var(var)
    if var.rank > 0 then
        return -- only allocate scalars (scalars are the only real thing)
    end
    var.vec = Vec.new(self.lengths.cell, var.init)
    if var.has_sys then
        var.fvsys = B.new_fvsys(self.mesh)
    end
end

--
-- Program
--

---@class CHASMprogram
---@field name string
---@field domains CHASMdomain[]
---@field vars CHASMvar[]
---@field consts CHASMconst[]
---@field blocks CHASMblock[]
---@field ISA table<string, table>
local Program = {}
Program.__index = Program

local function new_chasm_program(name)
    return setmetatable({
        name = name,
        domains = {},
        vars = {},
        consts = {},
        ISA = require("jnl.fvm.chasm.isa"),
    }, Program)
end

function Program:domain(name)
    local domain = new_domain(self, name)
    self.domains[name] = domain
    return domain
end

---@param name string
---@param value number
---@return CHASMconst
function Program:const(name, value)
    V.identifier(name, "CHASM const name")
    local k = new_constant(name, value)
    if self.consts[k.name] then
        error(string.format("const '%s' already exists", name), 2)
    end
    return k
end

---@param name string
---@param init number?
---@return CHASMvar
function Program:scalar(name, init)
    V.identifier(name, "CHASM:scalar(name)")
    local default = self.domains["default"]
    if not default then
        default = new_domain(self, "default")
        self.domains["default"] = default
    end
    local var = new_scalar(default, name, init)
    if self.vars[var.name] then
        error(string.format("var '%s' already exists", name), 2)
    end
    self.vars[var.name] = var
    return var
end

---@param name string
---@param init number?|table?
---@return CHASMvar
function Program:vector(name, init)
    V.identifier(name, "CHASM new_vector name")
    local default = self.domains["default"]
    if not default then
        default = new_domain(self, "default")
        self.domains["default"] = default
    end
    local var = new_vector(default, name, init)
    if self.vars[var.name] then
        error(string.format("var '%s' already exists", name), 2)
    end
    self.vars[var.name] = var
    self.vars[var.x.name] = var.x
    self.vars[var.y.name] = var.y
    return var
end

---@param v string|CHASMvar
---@return CHASMvar
function Program:get_var(v)
    if getmetatable(v) == Var and self.vars[v.name] then
        return self.vars[v.name]
    end

    if type(v) == "string" and self.vars[v] then
        return self.vars[v]
    end

    error(
        string.format("could not find var '%s' in program '%s'", v, self.name),
        2
    )
end

function Program:bind(mesh, bcs)
    local default = self.domains["default"]
    if not default then
        error(
            "cannot bind to default domain as no variables declared onto it",
            2
        )
    end

    default:bind(mesh, bcs)
    return self
end

function Program:allocate()
    -- allocate vars in their domains
    for _, var in pairs(self.vars) do
        local domain = self.domains[var.domain_name]
        domain:allocate_var(var)
    end
end

function Program:main(cb, iters)
    iters = iters or 1
    local name = self.name .. ":main"
    local block = require("jnl.fvm.chasm.block").new(self, name, iters)
    cb(block)
    self.main_block = block
    return self
end

function Program:start()
    local vm = VM.new(self)
    return vm:start()
end

--
-- Pretty printing program
--

local function prog_manifest_str(asm)
    local scalars = {}

    for name, var in pairs(asm.vars) do
        if var.rank == 0 then
            scalars[#scalars + 1] =
                string.format('local %s = asm:scalar("%s")', name, name)
        end
    end

    return table.concat(scalars, "\n") .. "\n"
end

local function prog_str(asm)
    local manifest_str = prog_manifest_str(asm)

    local block_strs = {}
    if asm.init_block then
        block_strs[#block_strs + 1] = tostring(asm.init_block)
    end
    if asm.main_block then
        block_strs[#block_strs + 1] = tostring(asm.main_block)
    end
    if asm.post_block then
        block_strs[#block_strs + 1] = tostring(asm.post_block)
    end

    local block_str = table.concat(block_strs, "\n\n")

    return manifest_str .. "\n" .. block_str
end

function Program:__tostring()
    return prog_str(self)
end

return {
    new = new_chasm_program,
}
