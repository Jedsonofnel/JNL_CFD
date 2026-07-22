-- [nfnl] fnl/nabla/fvm/bc.fnl
local _local_1_ = require("nabla.core.validation")
local assert_number = _local_1_["assert-number"]
local assert_oneof = _local_1_["assert-oneof"]
--[[ {:U {:__default {:kind "neumann-v" :ux-gn 4 :uy-gn 5} :north {:kind "dirichlet-v" :ux 5 :uy 4} :south {:kind "neumann-v" :ux-gn 4 :uy-gn 0} :west {:kind "nt-v" :n-kind "neumann" :n-val 1 :t-kind "neumann" :t-val 1}} :phi {:__default {:grad-n 0 :kind "neumann-s"} :east {:grad-n 9 :kind "neumann-s"} :north {:kind "dirichlet-s" :value 5} :south {:a 3 :b 2 :c 1 :kind "robin-s"}}} ]]
--[[ {:U {:__default (bc.neumann-v 0) :north (bc.dirichlet-v 5 4) :south (bc.neumann-v 4 0) :west (bc.nt-v "dirichlet" 0 "neumann" 1)} :phi {:__default (bc.neumann-s 0) :east (bc.neumann-s 9) :north (bc.dirichlet-s 5) :south (bc.robin-s 1 2 3)}} ]]
local function dirichlet_s(value)
  assert_number(value, "dirichlet-s value")
  return {kind = "dirichlet-s", value = value}
end
local function neumann_s(grad_n)
  assert_number(grad_n, "neumann-s grad-n")
  return {kind = "neumann-s", ["grad-n"] = grad_n}
end
local function robin_s(a, b, c)
  assert_number(a, "robin-s a")
  assert_number(b, "robin-s b")
  assert_number(c, "robin-s c")
  return {kind = "robin-s", a = a, b = b, c = c}
end
local function dirichlet_v(ux, _3fuy)
  local uy = (_3fuy or ux)
  assert_number(ux, "dirichlet-v ux")
  assert_number(uy, "dirichlet-v uy")
  return {kind = "dirichlet-v", ux = ux, uy = uy}
end
local function neumann_v(ux_gn, _3fuy_gn)
  local uy_gn = (_3fuy_gn or ux_gn)
  assert_number(ux_gn, "neumann-v ux-gn")
  assert_number(uy_gn, "neumann-v uy-gn")
  return {kind = "neumann-v", ["ux-gn"] = ux_gn, ["uy-gn"] = uy_gn}
end
local function nt_v(n_kind, n_val, t_kind, t_val)
  assert_oneof(n_kind, {"dirichlet", "neumann"}, "nt-v n-kind")
  assert_number(n_val, "nt-v n-val")
  assert_oneof(t_kind, {"dirichlet", "neumann"}, "nt-v t-kind")
  assert_number(t_val, "nt-v t-val")
  return {kind = "nt-v", ["n-kind"] = n_kind, ["n-val"] = n_val, ["t-kind"] = t_kind, ["t-val"] = t_val}
end
return {["dirichlet-s"] = dirichlet_s, ["neumann-s"] = neumann_s, ["robin-s"] = robin_s, ["dirichlet-v"] = dirichlet_v, ["neumann-v"] = neumann_v, ["nt-v"] = nt_v}
