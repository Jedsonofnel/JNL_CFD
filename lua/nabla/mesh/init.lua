-- [nfnl] fnl/nabla/mesh/init.fnl
local cartmesh2d = require("nabla.mesh.cartmesh2d")
local function resolve(_1_)
  local meshkind = _1_.meshkind
  local spec = _1_.spec
  if (meshkind == "cartmesh2d") then
    return cartmesh2d.resolve(spec)
  else
    local _ = meshkind
    return error(string.format("unrecognised mesh spec kind: '%s'", meshkind))
  end
end
return {cartmesh2d = cartmesh2d.build, resolve = resolve}
