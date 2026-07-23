-- [nfnl] fnl/nabla/core/mangle.fnl
local valid = require("nabla.core.validation")
local function reserved_3f(name)
  return name:match("^__(.+)")
end
local function reserved(name)
  if reserved_3f(name) then
    return name
  else
    return ("__" .. name)
  end
end
local function component(field, i)
  valid["assert-oneof"](i, {"x", "y"}, "component i")
  return (reserved(field) .. "_" .. i)
end
return {component = component}
