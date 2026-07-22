-- [nfnl] fnl/nabla/core/pool.fnl
local opt = require("nabla.core.optional")
local internal = opt.require("nabla.scratch_internal")
local _local_1_ = require("nabla.util")
local positive_integer_3f = _local_1_["positive-integer?"]
local function new(array_length)
  if not positive_integer_3f(array_length) then
    error("new pool array-length must be a positive integer", 2)
  else
  end
  return internal.new(array_length)
end
return {new = new}
