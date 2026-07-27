-- [nfnl] fnl/nabla/fvm/chasm.fnl
local _local_1_ = require("nabla.core")
local valid = _local_1_.valid
local mangle = _local_1_.mangle
local util = _local_1_.util
local array = _local_1_.array
local pool = _local_1_.pool
local bc = require("nabla.fvm.bc")
local meshlib = require("nabla.mesh")
local _local_2_ = require("nabla.fvm.bindings")
local new_fvsys = _local_2_["new-fvsys"]
local function scalar(name, _3fopts)
  valid["assert-identifier"](name, "chasm scalar name")
  local _4_
  do
    local t_3_ = _3fopts
    if (nil ~= t_3_) then
      t_3_ = t_3_.domain
    else
    end
    _4_ = t_3_
  end
  if _4_ then
    valid["assert-identifier"](_3fopts.domain, "chasm scalar opts.domain")
  else
  end
  local opts = (_3fopts or {})
  return {name = name, varkind = "scalar", init = opts.init, rank = 0, ["has-sys?"] = true, domain = (opts.domain or "__default")}
end
local function scalar_arr(name, _3fopts)
  valid["assert-identifier"](name, "chasm scalar-arr name")
  local _8_
  do
    local t_7_ = _3fopts
    if (nil ~= t_7_) then
      t_7_ = t_7_.domain
    else
    end
    _8_ = t_7_
  end
  if _8_ then
    valid["assert-identifier"](_3fopts.domain, "chasm scalar-arr opts.domain")
  else
  end
  local opts = (_3fopts or {})
  return {name = name, varkind = "scalar", init = opts.init, rank = 0, domain = (opts.domain or "__default"), ["facewise?"] = (opts["facewise?"] or opts["fw?"])}
end
local function parse_vector_init(name, _3finit)
  local and_11_ = (nil ~= _3finit)
  if and_11_ then
    local n = _3finit
    and_11_ = util["number?"](n)
  end
  if and_11_ then
    local n = _3finit
    return {n, n}
  else
    local and_13_ = ((_G.type(_3finit) == "table") and (nil ~= _3finit[1]) and (nil ~= _3finit[2]))
    if and_13_ then
      local x = _3finit[1]
      local y = _3finit[2]
      and_13_ = util["numbers?"](x, y)
    end
    if and_13_ then
      local x = _3finit[1]
      local y = _3finit[2]
      return {x, y}
    elseif (_3finit == nil) then
      return {0, 0}
    else
      local _ = _3finit
      return error(string.format("vector '%s' init: expected nil, number or [x y] pair, got %s", name, _3finit), 3)
    end
  end
end
local function vector(name, _3fopts)
  valid["assert-identifier"](name, "chasm vector name")
  local _17_
  do
    local t_16_ = _3fopts
    if (nil ~= t_16_) then
      t_16_ = t_16_.domain
    else
    end
    _17_ = t_16_
  end
  if _17_ then
    valid["assert-identifier"](_3fopts.domain, "chasm vector opts.domain")
  else
  end
  local opts = (_3fopts or {})
  local domain = (opts.domain or "__default")
  local _let_20_ = parse_vector_init(name, opts.init)
  local init_x = _let_20_[1]
  local init_y = _let_20_[2]
  local cname
  local function _21_(_241)
    return mangle.component(name, _241)
  end
  cname = _21_
  local x = {name = cname("x"), rank = 0, domain = domain, init = init_x, ["has-sys?"] = true}
  local y = {name = cname("y"), rank = 0, domain = domain, init = init_y, ["has-sys?"] = true}
  return {name = name, varkind = "vector", init = {init_x, init_y}, rank = 1, ["has-sys?"] = true, domain = domain, x = x, y = y}
end
local function vector_arr(name, _3fopts)
  valid["assert-identifier"](name, "chasm vector-arr name")
  local _23_
  do
    local t_22_ = _3fopts
    if (nil ~= t_22_) then
      t_22_ = t_22_.domain
    else
    end
    _23_ = t_22_
  end
  if _23_ then
    valid["assert-identifier"](_3fopts.domain, "chasm vector-arr opts.domain")
  else
  end
  local opts = (_3fopts or {})
  local domain = (opts.domain or "__default")
  local facewise_3f = (opts["facewise?"] or opts["fw?"])
  local _let_26_ = parse_vector_init(name, opts.init)
  local init_x = _let_26_[1]
  local init_y = _let_26_[2]
  local cname
  local function _27_(_241)
    return mangle.component(name, _241)
  end
  cname = _27_
  local x = {name = cname("x"), init = init_x, domain = domain, ["facewise?"] = facewise_3f, rank = 0}
  local y = {name = cname("y"), init = init_y, domain = domain, ["facewise?"] = facewise_3f, rank = 0}
  return {name = name, varkind = "vector", init = {init_x, init_y}, rank = 1, domain = domain, x = x, y = y, ["facewise?"] = facewise_3f}
end
local function block(name, instructions, _3fopts)
  valid["assert-identifier"](name, "chasm block name")
  if (#instructions == 0) then
    error(string.format("Block '%s': instruction array must have at least one instruction", name))
  else
  end
  local opts = (_3fopts or {})
  return {name = name, instructions = instructions, ["max-iters"] = (opts["max-iters"] or 1), convergence = opts.convergence}
end
local function get_components(v)
  if (0 < v.rank) then
    return util["concat-lists!"](util["concat-lists!"]({v.x, v.y}, (get_components(v.x) or {})), (get_components(v.y) or {}))
  else
    return nil
  end
end
--[[ (let [v (vector "jedn")] (get-components v)) ]]
local function expand_vars_with_components_21(var_map)
  for _, v in pairs(var_map) do
    if (0 < v.rank) then
      for _0, cv in ipairs(get_components(v)) do
        var_map[cv.name] = cv
      end
    else
    end
  end
  return nil
end
--[[ (let [s1 (scalar "s1") s2 (scalar "s2") v1 (vector "v1") v2 (vector "v2") vars {:s1 s1 :s2 s2 :v1 v1 :v2 v2}] (expand-vars-with-components! vars) vars) ]]
local function program(name, var_list, main_block)
  valid["assert-identifier"](name, "chasm program name")
  if (#var_list == 0) then
    error(string.format("Program '%s': var array must have at least one var"))
  else
  end
  local var_map = {}
  local var_map0
  do
    local tbl_21_ = var_map
    for _, v in ipairs(var_list) do
      local k_22_, v_23_
      if var_map[v.name] then
        k_22_, v_23_ = error(string.format("Program '%s': var '%s' appears at least twice in var array", name, v.name))
      else
        k_22_, v_23_ = v.name, v
      end
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    var_map0 = tbl_21_
  end
  local domains
  do
    local domains0 = {}
    for _, v in ipairs(var_list) do
      if not domains0[v.domain] then
        domains0[v.domain] = {name = v.domain}
        domains0 = domains0
      else
        domains0 = nil
      end
    end
    domains = domains0
  end
  expand_vars_with_components_21(var_map0)
  return {name = name, vars = var_map0, ["main-block"] = main_block, domains = domains}
end
--[[ (program "someprogram" [(scalar "s1") (vector "v1" {:domain "new"})] nil) ]]
local function get_domain_vars(vars, domain_name)
  local tbl_21_ = {}
  for vn, v in pairs(vars) do
    local k_22_, v_23_
    if (v.domain == domain_name) then
      k_22_, v_23_ = vn, v
    else
      k_22_, v_23_ = nil
    end
    if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
      tbl_21_[k_22_] = v_23_
    else
    end
  end
  return tbl_21_
end
local function allocate_domain(domain_name, mesh_spec, bc_spec, fields)
  local mesh = meshlib.resolve(mesh_spec)
  local _let_37_ = bc.resolve(bc_spec, fields, mesh:patches())
  local warnings = _let_37_.warnings
  local bcs = _let_37_.bcs
  local num_cells = mesh:n_cells()
  local num_faces = mesh:n_faces()
  return {warnings = warnings, domains = {[domain_name] = {name = domain_name, mesh = mesh, bcs = bcs, ["num-cells"] = num_cells, ["num-faces"] = num_faces, ["pool-cells"] = pool.new(num_cells), ["pool-faces"] = pool.new(num_faces)}}}
end
local function allocate_domains(_38_, mesh_spec, bc_spec)
  local domains = _38_.domains
  local vars = _38_.vars
  local domain_names
  do
    local tbl_26_ = {}
    local i_27_ = 0
    for dn, _ in pairs(domains) do
      local val_28_ = dn
      if (nil ~= val_28_) then
        i_27_ = (i_27_ + 1)
        tbl_26_[i_27_] = val_28_
      else
      end
    end
    domain_names = tbl_26_
  end
  if (#domain_names == 1) then
    local dn = domain_names[1]
    local fields = get_domain_vars(vars, dn)
    return allocate_domain(dn, mesh_spec, bc_spec, fields)
  else
    local per_domain
    do
      local tbl_26_ = {}
      local i_27_ = 0
      for dn, _ in pairs(domains) do
        local val_28_ = allocate_domain(dn, mesh_spec, bc_spec, get_domain_vars(vars, dn))
        if (nil ~= val_28_) then
          i_27_ = (i_27_ + 1)
          tbl_26_[i_27_] = val_28_
        else
        end
      end
      per_domain = tbl_26_
    end
    return {warnings = util["concat-all"]("warnings", per_domain), domains = util["concat-all"]("domains", per_domain)}
  end
end
local function allocate_arrays(domains, vars)
  local tbl_21_ = {}
  for name, v in pairs(vars) do
    local k_22_, v_23_
    if (v.rank == 0) then
      local domain = domains[v.domain]
      local function _42_()
        if v["facewise?"] then
          return array.new(domain["num-faces"], v.init)
        else
          return array.new(domain["num-cells"], v.init)
        end
      end
      k_22_, v_23_ = name, _42_()
    else
      k_22_, v_23_ = nil
    end
    if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
      tbl_21_[k_22_] = v_23_
    else
    end
  end
  return tbl_21_
end
local function allocate_systems(domains, vars)
  local tbl_21_ = {}
  for name, v in pairs(vars) do
    local k_22_, v_23_
    if (v.rank == 0) then
      local domain = domains[v.domain]
      local function _45_()
        if v["has-sys?"] then
          return new_fvsys(domain.mesh)
        else
          return nil
        end
      end
      k_22_, v_23_ = name, _45_()
    else
      k_22_, v_23_ = nil
    end
    if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
      tbl_21_[k_22_] = v_23_
    else
    end
  end
  return tbl_21_
end
local function compile(program_spec, mesh_spec, bc_spec)
  local _let_48_ = allocate_domains(program_spec, mesh_spec, bc_spec)
  local dwarnings = _let_48_.warnings
  local domains = _let_48_.domains
  local arrays = allocate_arrays(domains, program_spec.vars)
  local systems = allocate_systems(domains, program_spec.vars)
  if (nil ~= next(dwarnings)) then
    print(string.format("Compilation warnings for program '%s'\n%s", program_spec.name, table.concat(dwarnings, "\n")))
  else
  end
  return {name = program_spec.name, ["main-block"] = program_spec["main-block"], vars = program_spec.vars, domains = domains, arrays = arrays, systems = systems}
end
local function get_var(rt, name)
  return (rt.vars[name] or error(("unknown var '" .. name .. "'")))
end
local function get_sys(rt, name)
  return rt.systems[name]
end
local function get_array(rt, name)
  return rt.arrays[name]
end
local function get_const(rt, name)
  return rt.consts[name].value
end
local function get_sys_2bmesh(rt, name)
  local v = get_var(rt, name)
  local domain = rt.domains[v.domain]
  return {sys = get_sys(rt, name), mesh = domain.mesh}
end
local function get_sys_2bmesh_2bbcs(rt, name)
  local v = get_var(rt, name)
  local domain = rt.domains[v.domain]
  return {sys = get_sys(rt, name), mesh = domain.mesh, bcs = domain.bcs}
end
local function get_pool_cells(rt, name)
  local v = get_var(rt, name)
  return rt.domains[v.domain]["pool-cells"]
end
local function check_convergence(_pred, _ctx)
  return false
end
local function run_outer_iter_21(_rt, __3fblock, __3fdepth)
  return error("this is a forward declaration")
end
local function run_block_21(rt, block0, ctx, depth)
  for _, inst in ipairs(block0.instructions) do
    if inst.instructions then
      run_outer_iter_21(rt, inst, (1 + depth))
    else
      local isa = require("nabla.fvm.instructions")
      local instr_exec_fn = isa[inst.op].exec
      local record = instr_exec_fn(rt, ctx, inst)
      if record then
        coroutine.yield(record)
      else
      end
    end
  end
  return nil
end
local function run_outer_iter_210(rt, block0, _3fdepth, _3fiter)
  local iter = (_3fiter or 1)
  local depth = (_3fdepth or 1)
  local ctx = {["block-name"] = block0.name, depth = (_3fdepth or 1), iter = (_3fiter or 1)}
  run_block_21(rt, block0, ctx, depth)
  if (check_convergence(block0.convergence, ctx) or (block0["max-iters"] <= iter)) then
    return ctx
  else
    return run_outer_iter_210(rt, block0, depth, (1 + iter))
  end
end
local function add_defaults_to_result_21(result)
  if not result.status then
    result.status = "running"
    return nil
  else
    return nil
  end
end
local function step_21(rt)
  if not rt.co then
    local function _54_()
      local final = run_outer_iter_210(rt, rt["main-block"], 1)
      final.status = "done"
      return coroutine.yield(final)
    end
    rt.co = coroutine.create(_54_)
  else
  end
  local ok, result = coroutine.resume(rt.co)
  if not ok then
    return {status = "error", error = result}
  else
    add_defaults_to_result_21(result)
    return result
  end
end
local function run_all_21(rt)
  local function loop(result)
    if (result.status == "running") then
      return loop(step_21(rt))
    else
      if (result.status == "error") then
        return error(("VM execution error: " .. result.error))
      else
        return result
      end
    end
  end
  return loop(step_21(rt))
end
return {scalar = scalar, ["scalar-arr"] = scalar_arr, vector = vector, ["vector-arr"] = vector_arr, block = block, program = program, compile = compile, ["step!"] = step_21, ["run-all!"] = run_all_21, ["get-var"] = get_var, ["get-sys"] = get_sys, ["get-array"] = get_array, ["get-const"] = get_const, ["get-sys+mesh"] = get_sys_2bmesh, ["get-sys+mesh+bcs"] = get_sys_2bmesh_2bbcs, ["get-pool-cells"] = get_pool_cells}
