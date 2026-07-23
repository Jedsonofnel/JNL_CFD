-- [nfnl] fnl/nabla/core/pool.fnl
local opt = require("nabla.core.optional")
local util = require("nabla.core.util")
local internal = opt.require("nabla.scratch_internal")
local function new(array_length)
  if not util["positive-integer?"](array_length) then
    error("new pool array-length must be a positive integer", 2)
  else
  end
  return internal.new(array_length)
end
return {new = new}
