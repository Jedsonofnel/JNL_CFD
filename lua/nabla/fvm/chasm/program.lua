-- [nfnl] lua/nabla/fvm/chasm/program.fnl
local _local_1_ = require("nabla.core.mangle")
local component = _local_1_.component
local _local_2_ = require("nabla.core.validation")
local assert_identifier = _local_2_["assert-identifier"]
local array = require("nabla.core.array")
local pool = require("nabla.core.pool")
local _local_3_ = require("nabla.util")
local numbers_3f = _local_3_["numbers?"]
local _local_4_ = require("nabla.fvm.bindings")
local new_fvsys = _local_4_["new-fvsys"]
local function new_constant(name, value)
  local function _5_(self)
    return self.name
  end
  return setmetatable({name = name, value = value, rank = 0, kind = "constant"}, {__tostring = _5_})
end
local Var = {}
Var.__index = Var
Var.__tostring = function(self)
  return self.name
end
local function new_scalar_var(_6_, name, init, opts)
  local domain_name = _6_.name
  local opts0 = (opts or {})
  local has_sys_3f = (opts0["has-sys?"] or false)
  local facewise_3f = (opts0["facewise?"] or false)
  local init0 = (init or 0)
  return setmetatable({["domain-name"] = domain_name, name = name, rank = 0, kind = "scalar", ["has-sys?"] = has_sys_3f, ["facewise?"] = facewise_3f, init = init0}, Var)
end
local function new_vector_var(_7_, name, init, opts)
  local domain_name = _7_.name
  local init0
  local and_8_ = ((_G.type(init) == "table") and (nil ~= init[1]) and (nil ~= init[2]))
  if and_8_ then
    local x = init[1]
    local y = init[2]
    and_8_ = numbers_3f(x, y)
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
  local opts0 = (opts or {})
  local has_sys_3f = (opts0["has-sys?"] or false)
  local facewise_3f = (opts0["facewise?"] or false)
  return setmetatable({["domain-name"] = domain_name, name = name, rank = 1, kind = "vector", ["has-sys?"] = has_sys_3f, ["facewise?"] = facewise_3f, init = init0, x = x, y = y}, Var)
end
local function new_scalar_arr(domain, name, init)
  return new_scalar_var(domain, name, init, {["facewise?"] = false, ["has-sys?"] = false})
end
local function new_scalar_arr_fw(domain, name, init)
  return new_scalar_var(domain, name, init, {["facewise?"] = true, ["has-sys?"] = false})
end
local function new_scalar_prog(domain, name, init)
  return new_scalar_var(domain, name, init, {["has-sys?"] = true, ["facewise?"] = false})
end
local function new_vector_arr(domain, name, init)
  return new_vector_var(domain, name, init, {["facewise?"] = false, ["has-sys?"] = false})
end
local function new_vector_arr_fw(domain, name, init)
  return new_vector_var(domain, name, init, {["facewise?"] = true, ["has-sys?"] = false})
end
local function new_vector_prog(domain, name, init)
  return new_vector_var(domain, name, init, {["has-sys?"] = true, ["facewise?"] = false})
end
Var["residual-lt"] = function(self, val)
  return {kind = "lt", src = "residual", key = self.name, val = val}
end
Var["residual-gt"] = function(self, val)
  return {kind = "lg", src = "residual", key = self.name, val = val}
end
local Domain = {}
Domain.__index = Domain
local function new_domain(prog, name)
  return setmetatable({prog = prog, name = name, vars = {}}, Domain)
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
local function domain_add_scalar_arr_21(domain, name, init)
  assert_identifier(name, "CHASM scalar name")
  assert_new_to_prog(domain.prog, name)
  local reg = new_scalar_arr(domain, name, init)
  domain.prog.vars[name] = reg
  return reg
end
local function domain_add_scalar_arr_fw_21(domain, name, init)
  assert_identifier(name, "CHASM scalar name")
  assert_new_to_prog(domain.prog, name)
  local reg = new_scalar_arr_fw(domain, name, init)
  domain.prog.vars[name] = reg
  return reg
end
local function domain_add_scalar_prog_21(domain, name, init)
  assert_identifier(name, "CHASM scalar name")
  assert_new_to_prog(domain.prog, name)
  local field = new_scalar_prog(domain, name, init)
  domain.prog.vars[name] = field
  return field
end
local function domain_add_vector_arr_21(domain, name, init)
  assert_identifier(name, "CHASM vector name")
  assert_new_to_prog(domain.prog, name)
  local reg = new_vector_arr(domain, name, init)
  domain.prog.vars[name] = reg
  domain.prog.vars[reg.x.name] = reg.x
  domain.prog.vars[reg.y.name] = reg.y
  return reg
end
local function domain_add_vector_arr_fw_21(domain, name, init)
  assert_identifier(name, "CHASM vector name")
  assert_new_to_prog(domain.prog, name)
  local reg = new_vector_arr_fw(domain, name, init)
  domain.prog.vars[name] = reg
  domain.prog.vars[reg.x.name] = reg.x
  domain.prog.vars[reg.y.name] = reg.y
  return reg
end
local function domain_add_vector_prog_21(domain, name, init)
  assert_identifier(name, "CHASM vector name")
  assert_new_to_prog(domain.prog, name)
  local field = new_vector_prog(domain, name, init)
  domain.prog.vars[name] = field
  domain.prog.vars[field.x.name] = field.x
  domain.prog.vars[field.y.name] = field.y
  return field
end
Domain["scalar-arr"] = function(self, name, init)
  return domain_add_scalar_arr_21(self, name, init)
end
Domain["scalar-arr-fw"] = function(self, name, init)
  return domain_add_scalar_arr_fw_21(self, name, init)
end
Domain["scalar-prog"] = function(self, name, init)
  return domain_add_scalar_prog_21(self, name, init)
end
Domain["vector-reg"] = function(self, name, init)
  return domain_add_vector_arr_21(self, name, init)
end
Domain["vector-reg-fw"] = function(self, name, init)
  return domain_add_vector_arr_fw_21(self, name, init)
end
Domain["vector-prog"] = function(self, name, init)
  return domain_add_vector_prog_21(self, name, init)
end
local function domain_bind_21(domain, mesh, bcs)
  assert(mesh, "mesh required for binding")
  assert(bcs, "bccs required for binding")
  do
    local warnings, errors = bcs:validate(mesh)
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
    domain["pool-cells"] = pool.new(n_cells)
    domain["pool-faces"] = pool.new(n_faces)
  end
  return domain
end
Domain.bind = function(self, mesh, bcs)
  return domain_bind_21(self, mesh, bcs)
end
local Program = {}
Program.__index = Program
local function new_program(name)
  return setmetatable({name = name, domains = {}, vars = {}, consts = {}, ISA = require("nabla.fvm.chasm.isa")}, Program)
end
local function program_get_or_create_default_21(_16_)
  local domains = _16_.domains
  local prog = _16_
  local or_17_ = domains.default
  if not or_17_ then
    local d = new_domain(prog, "default")
    domains.default = d
    or_17_ = d
  end
  return or_17_
end
local function program_add_const_21(prog, name, value)
  assert_identifier(name, "program constant name")
  assert_new_to_prog(prog, name)
  local constant = new_constant(name, value)
  prog.consts[name] = constant
  return constant
end
local function add_scalar_arr_21(prog, name, init)
  return domain_add_scalar_arr_21(program_get_or_create_default_21(prog), name, init)
end
local function add_scalar_arr_fw_21(prog, name, init)
  return domain_add_scalar_arr_fw_21(program_get_or_create_default_21(prog), name, init)
end
local function add_scalar_prog_21(prog, name, init)
  return domain_add_scalar_prog_21(program_get_or_create_default_21(prog), name, init)
end
local function add_vector_arr_21(prog, name, init)
  return domain_add_vector_arr_21(program_get_or_create_default_21(prog), name, init)
end
local function add_vector_arr_fw_21(prog, name, init)
  return domain_add_vector_arr_fw_21(program_get_or_create_default_21(prog), name, init)
end
local function add_vector_prog_21(prog, name, init)
  return domain_add_vector_prog_21(program_get_or_create_default_21(prog), name, init)
end
local function program_get_var(_19_, v)
  local vars = _19_.vars
  local prog_name = _19_["prog-name"]
  local and_20_ = ((_G.type(v) == "table") and (nil ~= v.name))
  if and_20_ then
    local name = v.name
    and_20_ = ((type(name) == "string") and vars[name])
  end
  if and_20_ then
    local name = v.name
    return vars[name]
  else
    local and_22_ = (nil ~= v)
    if and_22_ then
      local name = v
      and_22_ = ((type(name) == "string") and vars[name])
    end
    if and_22_ then
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
local function allocate_var_21(v, _25_)
  local n_cells = _25_["n-cells"]
  local n_faces = _25_["n-faces"]
  local mesh = _25_.mesh
  if (v.rank == 0) then
    if v["facewise?"] then
      v.array = array.new(n_faces, v.init)
    else
      v.array = array.new(n_cells, v.init)
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
local function program_write_main_21(program, cb, _3fiters)
  local iters = (_3fiters or 1)
  local _let_29_ = require("nabla.fvm.chasm.block")
  local new_block = _let_29_.new
  local main = new_block(program, "main", iters)
  cb(main)
  program["main-block"] = main
  return main
end
Program["scalar-arr"] = function(self, name, init)
  return domain_add_scalar_arr_21(program_get_or_create_default_21(self), name, init)
end
Program["scalar-arr-fw!"] = function(self, name, init)
  return domain_add_scalar_arr_fw_21(program_get_or_create_default_21(self), name, init)
end
Program["scalar-prog!"] = function(self, name, init)
  return domain_add_scalar_prog_21(program_get_or_create_default_21(self), name, init)
end
Program["vector-arr"] = function(self, name, init)
  return domain_add_vector_arr_21(program_get_or_create_default_21(self), name, init)
end
Program["vector-arr-fw!"] = function(self, name, init)
  return domain_add_vector_arr_fw_21(program_get_or_create_default_21(self), name, init)
end
Program["vector-prog!"] = function(self, name, init)
  return domain_add_vector_prog_21(program_get_or_create_default_21(self), name, init)
end
Program.const = function(self, name, value)
  return program_add_const_21(self, name, value)
end
Program["get-var"] = function(self, v)
  return program_get_var(self, v)
end
Program["get-array"] = function(self, v)
  return program_get_var(self, v)[array]
end
Program.main = function(self, cb, _3fiters)
  return program_write_main_21(self, cb, _3fiters)
end
Program.bind = function(self, mesh, bcs)
  return program_bind_21(self, mesh, bcs)
end
Program.start = function(self)
  local vm_module = require("nabla.fvm.chasm.vm")
  local new_vm = vm_module.new(self)
  vm_module["start!"](new_vm)
  return new_vm
end
return {new = new_program, ["program-write-main!"] = program_write_main_21, ["allocate!"] = program_allocate_21, ["program-get-var"] = program_get_var, ["add-scalar-arr!"] = add_scalar_arr_21, ["add-scalar-arr-fw!"] = add_scalar_arr_fw_21, ["add-scalar-prog!"] = add_scalar_prog_21, ["add-vector-arr!"] = add_vector_arr_21, ["add-vector-arr-fw!"] = add_vector_arr_fw_21, ["add-vector-prog!"] = add_vector_prog_21}
