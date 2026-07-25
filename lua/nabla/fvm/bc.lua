-- [nfnl] fnl/nabla/fvm/bc.fnl
local _local_1_ = require("nabla.core.validation")
local assert_number = _local_1_["assert-number"]
local assert_oneof = _local_1_["assert-oneof"]
local util = require("nabla.core.util")
--[[ {:U {:__default {:kind "neumann-v" :ux-gn 4 :uy-gn 5} :north {:kind "dirichlet-v" :ux 5 :uy 4} :south {:kind "neumann-v" :ux-gn 4 :uy-gn 0} :west {:kind "nt-v" :n-kind "neumann" :n-val 1 :t-kind "neumann" :t-val 1}} :phi {:__default {:grad-n 0 :kind "neumann-s"} :east {:grad-n 9 :kind "neumann-s"} :north {:kind "dirichlet-s" :value 5} :south {:a 3 :b 2 :c 1 :kind "robin"}}} ]]
--[[ {:U {:__default (bc.neumann-v 0) :north (bc.dirichlet-v 5 4) :south (bc.neumann-v 4 0) :west (bc.nt-v "dirichlet" 0 "neumann" 1)} :phi {:__default (bc.neumann-s 0) :east (bc.neumann-s 9) :north (bc.dirichlet-s 5) :south (bc.robin 1 2 3)}} ]]
local function dirichlet_s(value)
  assert_number(value, "dirichlet-s value")
  return {kind = "dirichlet-s", rank = 0, value = value}
end
local function neumann_s(grad_n)
  assert_number(grad_n, "neumann-s grad-n")
  return {kind = "neumann-s", rank = 0, ["grad-n"] = grad_n}
end
local function robin(a, b, c)
  assert_number(a, "robin a")
  assert_number(b, "robin b")
  assert_number(c, "robin c")
  return {kind = "robin", rank = 0, a = a, b = b, c = c}
end
local function dirichlet_v(ux, _3fuy)
  local uy = (_3fuy or ux)
  assert_number(ux, "dirichlet-v ux")
  assert_number(uy, "dirichlet-v uy")
  return {kind = "dirichlet-v", rank = 1, ux = ux, uy = uy}
end
local function neumann_v(ux_gn, _3fuy_gn)
  local uy_gn = (_3fuy_gn or ux_gn)
  assert_number(ux_gn, "neumann-v ux-gn")
  assert_number(uy_gn, "neumann-v uy-gn")
  return {kind = "neumann-v", rank = 1, ["ux-gn"] = ux_gn, ["uy-gn"] = uy_gn}
end
local function nt_v(n_kind, n_val, t_kind, t_val)
  assert_oneof(n_kind, {"dirichlet", "neumann"}, "nt-v n-kind")
  assert_number(n_val, "nt-v n-val")
  assert_oneof(t_kind, {"dirichlet", "neumann"}, "nt-v t-kind")
  assert_number(t_val, "nt-v t-val")
  return {kind = "nt-v", rank = 1, ["n-kind"] = n_kind, ["n-val"] = n_val, ["t-kind"] = t_kind, ["t-val"] = t_val}
end
local function dirichlet(ux, _3fuy)
  if _3fuy then
    return dirichlet_v(ux, _3fuy)
  else
    assert_number(ux, "dirichlet ux")
    return {kind = "dirichlet-poly", ["poly?"] = true, value = ux}
  end
end
local function neumann(ux_gn, _3fuy_gn)
  if _3fuy_gn then
    return neumann_v(ux_gn, _3fuy_gn)
  else
    assert_number(ux_gn, "neumann ux-gn")
    return {kind = "neumann-poly", ["poly?"] = true, ["grad-n"] = ux_gn}
  end
end
local function nograd()
  return neumann(0)
end
local function validate_bc_rank(field, patch_name, bc)
  if (not bc["poly?"] and (field.rank ~= bc.rank)) then
    return string.format("field '%s' (rank %d): BC '%s' on patch '%s' is rank %d", field.name, field.rank, bc.kind, patch_name, bc.rank)
  else
    return nil
  end
end
local function validate_bc_patch_exists(field, patch_name, patches)
  if ((patch_name ~= "__default") and not patches[patch_name]) then
    return string.format("field '%s': unknown patch '%s' in BC set", field.name, patch_name)
  else
    return nil
  end
end
local function validate_bc_field(field, bc_map, patches)
  if not bc_map then
    return {errors = {string.format("BCs not set for field %s", field.name)}, warnings = {}}
  else
    local _6_
    do
      local tbl_26_ = {}
      local i_27_ = 0
      for patch_name, bc in pairs(bc_map) do
        local val_28_ = validate_bc_rank(field, patch_name, bc)
        if (nil ~= val_28_) then
          i_27_ = (i_27_ + 1)
          tbl_26_[i_27_] = val_28_
        else
        end
      end
      _6_ = tbl_26_
    end
    local function _8_()
      local tbl_26_ = {}
      local i_27_ = 0
      for patch_name, _ in pairs(bc_map) do
        local val_28_ = validate_bc_patch_exists(field, patch_name, patches)
        if (nil ~= val_28_) then
          i_27_ = (i_27_ + 1)
          tbl_26_[i_27_] = val_28_
        else
        end
      end
      return tbl_26_
    end
    local _10_
    do
      local tbl_26_ = {}
      local i_27_ = 0
      for patch_name, _ in pairs(patches) do
        local val_28_
        if (not bc_map[patch_name] and not bc_map.__default) then
          val_28_ = string.format("field '%s': patch '%s' uncovered, implicitly nograd", field.name, patch_name)
        else
          val_28_ = nil
        end
        if (nil ~= val_28_) then
          i_27_ = (i_27_ + 1)
          tbl_26_[i_27_] = val_28_
        else
        end
      end
      _10_ = tbl_26_
    end
    return {errors = util["concat-lists!"](_6_, _8_()), warnings = _10_}
  end
end
local function validate(bcs, fields, patches)
  local per_field
  do
    local tbl_26_ = {}
    local i_27_ = 0
    for field_name, field in pairs(fields) do
      local val_28_ = validate_bc_field(field, bcs[field_name], patches)
      if (nil ~= val_28_) then
        i_27_ = (i_27_ + 1)
        tbl_26_[i_27_] = val_28_
      else
      end
    end
    per_field = tbl_26_
  end
  return {errors = util["concat-all"]("errors", per_field), warnings = util["concat-all"]("warnings", per_field)}
end
local function resolve_poly(rank, bc_desc)
  if ((_G.type(bc_desc) == "table") and (bc_desc.kind == "dirichlet-poly") and (nil ~= bc_desc.value)) then
    local value = bc_desc.value
    if (rank == 0) then
      return dirichlet_s(value)
    elseif (rank == 1) then
      return dirichlet_v(value, value)
    else
      return error("resolve-poly: unsupported rank")
    end
  elseif ((_G.type(bc_desc) == "table") and (bc_desc.kind == "neumann-poly") and (nil ~= bc_desc["grad-n"])) then
    local grad_n = bc_desc["grad-n"]
    if (rank == 0) then
      return neumann_s(grad_n)
    elseif (rank == 1) then
      return neumann_v(grad_n, grad_n)
    else
      return error("resolve-poly: unsupported rank")
    end
  else
    return nil
  end
end
--[[ (resolve-poly 0 (neumann 0)) ]]
local function resolve_bc_field(_18_, bc_map, patches)
  local rank = _18_.rank
  local default_raw = bc_map.__default
  local default
  if default_raw["poly?"] then
    default = resolve_poly(rank, default_raw)
  else
    default = default_raw
  end
  local tbl_21_ = {}
  for patch_name, _ in pairs(patches) do
    local k_22_, v_23_
    local function _20_()
      local bc_desc = bc_map[patch_name]
      if not bc_desc then
        return default
      elseif bc_desc["poly?"] then
        return resolve_poly(rank, bc_desc)
      else
        return bc_desc
      end
    end
    k_22_, v_23_ = patch_name, _20_()
    if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
      tbl_21_[k_22_] = v_23_
    else
    end
  end
  return tbl_21_
end
local function resolve(bcs, fields, patches)
  local _let_23_ = validate(bcs, fields, patches)
  local errors = _let_23_.errors
  local warnings = _let_23_.warnings
  local validation_results = _let_23_
  if (#errors ~= 0) then
    return validation_results
  else
    local resolved_bcs
    do
      local tbl_21_ = {}
      for field_name, field in pairs(fields) do
        local k_22_, v_23_ = field_name, resolve_bc_field(field, bcs[field_name], patches)
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      resolved_bcs = tbl_21_
    end
    return {warnings = warnings, bcs = resolved_bcs}
  end
end
return {DEFAULT = "__default", ["dirichlet-s"] = dirichlet_s, ["neumann-s"] = neumann_s, robin = robin, ["dirichlet-v"] = dirichlet_v, ["neumann-v"] = neumann_v, ["nt-v"] = nt_v, neumann = neumann, dirichlet = dirichlet, nograd = nograd, validate = validate, resolve = resolve}
