-- [nfnl] lua/nabla/fvm/chasm/program.fnl
local _local_1_ = require("nabla.core.mangle")
local component = _local_1_.component
local _local_2_ = require("nabla.core.validation")
local assert_identifier = _local_2_["assert-identifier"]
local _local_3_ = require("nabla.core.vec")
local new_vec = _local_3_.new
local _local_4_ = require("nabla.core.pool")
local new_pool = _local_4_.new
local _local_5_ = require("nabla.fvm.bindings")
local new_fvsys = _local_5_["new-fvsys"]
local Var = {}
Var.__index = Var
Var.__tostring = function(self)
  return self.name
end
local function new_scalar_var(_6_, name, init)
  local domain_name = _6_.name
  return setmetatable({["domain-name"] = domain_name, name = name, rank = 0, kind = "scalar", init = (init or 0), ["facewise?"] = false, ["has-sys?"] = false}, Var)
end
local function new_vector_var(_7_, name, init)
  local domain_name = _7_.name
  local init0
  local and_8_ = ((_G.type(init) == "table") and (nil ~= init[1]) and (nil ~= init[2]))
  if and_8_ then
    local x = init[1]
    local y = init[2]
    and_8_ = ((type(x) == "number") and (type(y) == "number"))
  end
  if and_8_ then
    local x = init[1]
    local y = init[2]
    init0 = {x, y}
  else
    local and_10_ = (nil ~= init)
    if and_10_ then
      local n = init
      and_10_ = (type(n) == "number")
    end
    if and_10_ then
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
  local function _13_(self)
    return self.name
  end
  return setmetatable({name = name, value = value, rank = 0, kind = "constant"}, {__tostring = _13_})
end
local Domain = {}
Domain.__index = Domain
local function new_domain(prog, name)
  return setmetatable({prog = prog, name = name, vars = {}}, Domain)
end
Domain.scalar = function(self, name, init)
  assert_identifier(name, "CHASM scalar name")
  local v = new_scalar_var(self, name, init)
  if self.prog.vars[name] then
    return error(string.format("var '%s' already exists", name, 2))
  else
    self.prog.vars[name] = v
    return v
  end
end
local function domain_add_vector_21(domain, vname, vinit)
  assert_identifier(vname, "CHASM vector name")
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
    local _let_16_ = bcs:validate(mesh)
    local warnings = _let_16_[1]
    local errors = _let_16_[2]
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
    domain["pool-cells"] = new_pool(n_cells)
    domain["pool-faces"] = new_pool(n_faces)
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
local function program_get_or_create_default_21(_19_)
  local domains = _19_.domains
  local prog = _19_
  local or_20_ = domains.default
  if not or_20_ then
    local d = new_domain(prog, "default")
    domains.default = d
    or_20_ = d
  end
  return or_20_
end
local function exists_in_prog_3f(prog, name)
  return (prog.consts[name] or prog.vars[name])
end
local function assert_new_to_prog(prog, name)
  if exists_in_prog_3f(prog, name) then
    return error(string.format("name '%s' already exists in the program", name), 3)
  else
    return nil
  end
end
local function program_add_const_21(prog, name, value)
  assert_identifier(name, "program constant name")
  assert_new_to_prog(prog, name)
  local constant = new_constant(name, value)
  prog.consts[name] = constant
  return constant
end
local function program_add_scalar_21(prog, name, init)
  assert_identifier(name, "program scalar name")
  assert_new_to_prog(prog, name)
  local default = program_get_or_create_default_21(prog)
  local scalar = new_scalar_var(default, name, init)
  prog.vars[name] = scalar
  return scalar
end
local function program_add_vector_21(prog, name, init)
  assert_identifier(name, "program vector name")
  assert_new_to_prog(prog, name)
  local default = program_get_or_create_default_21(prog)
  local vector = new_vector_var(default, name, init)
  prog.vars[name] = vector
  prog.vars[vector.x.name] = vector.x
  prog.vars[vector.y.name] = vector.y
  return vector
end
local function program_get_var(_23_, v)
  local vars = _23_.vars
  local prog_name = _23_["prog-name"]
  local and_24_ = ((_G.type(v) == "table") and (nil ~= v.name))
  if and_24_ then
    local name = v.name
    and_24_ = ((type(name) == "string") and vars[name])
  end
  if and_24_ then
    local name = v.name
    return vars[name]
  else
    local and_26_ = (nil ~= v)
    if and_26_ then
      local name = v
      and_26_ = ((type(name) == "string") and vars[name])
    end
    if and_26_ then
      local name = v
      return vars[name]
    else
      local _ = v
      return error(string.format("could not find var '%s' in program '%s'", v, prog_name))
    end
  end
end
local function program_bind_21(program, mesh, bcs)
  local default = (program.domains.default or error("cannot bind to default domain as no variables declared onto it", 2))
  domain_bind_21(default, mesh, bcs)
  return program
end
local function allocate_var_21(v, _29_)
  local n_cells = _29_["n-cells"]
  local n_faces = _29_["n-faces"]
  local mesh = _29_.mesh
  if (v.rank == 0) then
    if v["facewise?"] then
      v.vec = new_vec(n_faces, v.init)
    else
      v.vec = new_vec(n_cells, v.init)
      if v["has-sys?"] then
        v.fvsys = new_fvsys(mesh)
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
Program.const = function(self, name, value)
  return program_add_const_21(self, name, value)
end
Program.scalar = function(self, name, init)
  return program_add_scalar_21(self, name, init)
end
Program.vector = function(self, name, init)
  return program_add_vector_21(self, name, init)
end
Program.get_var = function(self, v)
  return program_get_var(self, v)
end
Program.bind = function(self, mesh, bcs)
  return program_bind_21(self, mesh, bcs)
end
return {new = new_chasm_program, ["allocate!"] = program_allocate_21}
