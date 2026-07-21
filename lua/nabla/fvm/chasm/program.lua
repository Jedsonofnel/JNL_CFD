-- [nfnl] lua/nabla/fvm/chasm/program.fnl
local _local_1_ = require("nabla.core.mangle")
local component = _local_1_.component
local _local_2_ = require("nabla.core.validation")
local identifier = _local_2_.identifier
local Var = {}
Var.__index = Var
Var.__tostring = function(self)
  return self.name
end
local function new_scalar_var(_3_, name, init)
  local domain_name = _3_.name
  return setmetatable({["domain-name"] = domain_name, name = name, rank = 0, kind = "scalar", init = (init or 0), ["facewise?"] = false, ["has-sys?"] = false}, Var)
end
local function new_vector_var(_4_, name, init)
  local domain_name = _4_.name
  local init0
  local and_5_ = ((_G.type(init) == "table") and (nil ~= init[1]) and (nil ~= init[2]))
  if and_5_ then
    local x = init[1]
    local y = init[2]
    and_5_ = ((type(x) == "number") and (type(y) == "number"))
  end
  if and_5_ then
    local x = init[1]
    local y = init[2]
    init0 = {x, y}
  else
    local and_7_ = (nil ~= init)
    if and_7_ then
      local n = init
      and_7_ = (type(n) == "number")
    end
    if and_7_ then
      local n = init
      init0 = {n, n}
    elseif (init == nil) then
      init0 = {0, 0}
    else
      local _ = init
      init0 = error("vector init: expected number or [x y] pair", 3)
    end
  end
  local x = new_scalar_var({name = domain_name}, component(name, "x", init0[1]))
  local y = new_scalar_var({name = domain_name}, component(name, "y", init0[2]))
  return setmetatable({["domain-name"] = domain_name, name = name, rank = 1, kind = "vector", init = init0, x = x, y = y, ["facewise?"] = false, ["has-sys?"] = false}, Var)
end
Var.sys = function(self)
  self["has-sys?"] = true
  return self
end
Var.face = function(self)
  self["facewise?"] = true
  return self
end
Var.residual_lt = function(self, val)
  return {kind = "lt", src = "residual", key = self.name, val = val}
end
Var.residual_gt = function(self, val)
  return {kind = "lg", src = "residual", key = self.name, val = val}
end
local function new_constant(name, value)
  local function _10_(self)
    return self.name
  end
  return setmetatable({name = name, value = value, rank = 0, kind = "constant"}, {__tostring = _10_})
end
local Domain = {}
Domain.__index = Domain
local function new_domain(prog, name)
  return setmetatable({prog = prog, name = name, vars = {}}, Domain)
end
Domain.scalar = function(self, name, init)
  identifier(name, "CHASM scalar name")
  local v = new_scalar_var(self, name, init)
  if self.prog.vars[name] then
    return error(string.format("var '%s' already exists", name, 2))
  else
    self.prog.vars[name] = v
    return v
  end
end
local function domain_add_vector_21(domain, vname, vinit)
  identifier(vname, "CHASM vector name")
  local v = new_vector_var(domain, vname, vinit)
  if domain.prog.vars[vname] then
    return error(string.format("var '%s' already exists", vname, 3))
  else
    domain.prog.vars[vname] = v
    domain.prog.vars[v.x.name] = v.x
    domain.prog.vars[v.y.name] = v.y
    return v
  end
end
Domain.vector = function(self, name, init)
  return domain_add_vector_21(self, name, init)
end
local function domain_bind_21(domain, mesh, bcs)
  assert(mesh, "mesh required for binding")
  assert(bcs, "bccs required for binding")
  do
    local _let_13_ = bcs:validate(mesh)
    local warnings = _let_13_[1]
    local errors = _let_13_[2]
    if (#warnings > 0) then
      error(string.format("BC errors: \n%s", table.concat(errors, "\n  ")))
    else
    end
    if (#errors > 0) then
      error(string.format("BC warnings: \n%s", table.concat(warnings, "\n  ")))
    else
    end
  end
  domain.mesh = mesh
  domain.bcs = bcs
  do
    local n_cells = mesh:n_cells()
    local n_faces = mesh:n_faces()
    domain["n-cells"] = n_cells
    domain["n-faces"] = n_faces
    domain["pool-cells"] = __fnl_global__new_2dpool(n_cells)
    domain["pool-faces"] = __fnl_global__new_2dpool(n_faces)
  end
  return domain
end
Domain.bind = function(self, mesh, bcs)
  return domain_bind_21(self, mesh, bcs)
end
local Program = {}
Program.__index = Program
local function new_chasm_program(name)
  return setmetatable({name = name, domains = {}, vars = {}, consts = {}, ISA = nil}, Program)
end
local function program_bind_21(program, mesh, bcs)
  local default = (program.domains.default or error("cannot bind to default domain as no variables declared onto it", 2))
  domain_bind_21(default, mesh, bcs)
  return program
end
local function allocate_var_21(v, _16_)
  local n_cells = _16_["n-cells"]
  local n_faces = _16_["n-faces"]
  local mesh = _16_.mesh
  if (v.rank == 0) then
    if v["facewise?"] then
      v.vec = __fnl_global__new_2dvec(n_faces, v.init)
    else
      v.vec = __fnl_global__new_2dvec(n_cells, v.init)
      if v["has-sys?"] then
        v.fvsys = __fnl_global__new_2dfvsys(mesh)
      else
      end
    end
    return v
  else
    return nil
  end
end
local function program_allocate_21(program)
  for _, v in pairs(program.vars) do
    local domain = program.domains[v["domain-name"]]
    allocate_var_21(v, domain)
  end
  return nil
end
return {new = new_chasm_program}
