-- [nfnl] lua/nabla/mesh/cartmesh2d.fnl
local opt = require("nabla.core.optional")
local internal = opt.require("nabla.strucmesh2d_internal")
local _local_1_ = require("nabla.core.validation")
local assert_number = _local_1_["assert-number"]
local function build(width, height, nx, ny)
  assert_number(width, "cartmesh2d build width")
  assert_number(height, "cartmesh2d build height")
  assert_number(ny, "cartmesh2d build nx")
  assert_number(ny, "cartmesh2d build ny")
  return internal.cartmesh(width, height, nx, ny)
end
return {build = build, NORTH = "north", TOP = "north", EAST = "east", RIGHT = "east", SOUTH = "south", BOTTOM = "south", WEST = "west", LEFT = "west"}
