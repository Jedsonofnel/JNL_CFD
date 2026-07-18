-- jnl/fvm/chasm/program.lua
-- <jed@nelson.ac> // 2026-07-18

-- deps
local V = require("jnl.core.validation")

--
-- Vars
--

---@class CHASMvar
---@field name string
---@field rank integer
---@field has_sys boolean
---@domain CHASMdomain
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
    V.identifier(name, "CHASM:scalar(name)")
    init = init or 0.0
    local var = setmetatable({
        domain = domain,
        name = name,
        rank = 0,
        has_sys = false,
        init = init,
    }, Var)
    return var
end

function Var:sys()
    self.has_sys = true
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
---@param init number
---@return CHASMvar
function Domain:scalar(name, init)
    V.identifier(name, "CHASM scalar name")
    local var = new_scalar(self, name, init)
    if self.prog.vars[name] then
        error(string.format("var '%s' already exists", name), 2)
    end
    self.prog.vars[name] = var
    return var
end

---@param mesh Mesh2D
function Domain:bind(mesh, bcs)
    -- TODO validate bcs
    self.mesh = mesh
    self.bcs = bcs
    return self
end

--
-- Program
--

---@class CHASMprogram
---@field name string
---@field domains CHASMdomain[]
---@field vars CHASMvar[]
---@field blocks CHASMblock[]
---@field ISA table<string, table>
local Program = {}
Program.__index = Program

local function new_chasm_program(name)
    return setmetatable({
        name = name,
        domains = {},
        ISA = require("jnl.fvm.chasm.isa"),
    }, Program)
end

function Program:domain(name)
    local domain = new_domain(self, name)
    self.domains[name] = domain
    return domain
end

function Program:scalar(name, init)
    local default = self.domains["default"]
    if not default then
        self.domains["default"] = new_domain(self, "default")
    end
    local var = new_scalar(default, name, init)
    if self.vars[var.name] then
        error(string.format("var '%s' already exists", name), 2)
    end
    self.vars[var.name] = var
    return var
end

function Program:bind(mesh, bcs)
    local default = self.domains["default"]
    if not default then
        error(
            "cannot bind to default domain as no variables declared onto it",
            2
        )
    end
    -- TODO some mesh/bcs validation
    default.mesh = mesh
    default.bcs = bcs
    return self
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
        string.format("could not find var '%s' in program '%s'", v, self.name)
    )
end

--
-- Program part constructors
--

function Program:init(cb)
    local name = self.name .. ":init"
    local block = require("jnl.fvm.chasm.block").new(self, name, 1)
    cb(block)
    self.init = block
    return self
end

function Program:main(iters, cb)
    local name = self.name .. ":main"
    local block = require("jnl.fvm.chasm.block").new(self, name, iters)
    cb(block)
    self.main = block
    return self
end

function Program:post(cb)
    local name = self.name .. ":post"
    local block = require("jnl.fvm.chasm.block").new(self, name, 1)
    cb(block)
    self.post = block
    return self
end

return {
    new = new_chasm_program,
}
