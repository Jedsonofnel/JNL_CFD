-- [nfnl] fnl/nabla/core/array.fnl
local opt = require("nabla.core.optional")
local internal = opt.require("nabla.array_internal")
local function new(len, init)
  return internal.new(len, (init or 0))
end
local function view(src, offset, len)
  return internal.view(src, offset, len)
end
return {new = new, view = view}
