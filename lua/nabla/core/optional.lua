-- [nfnl] fnl/nabla/core/optional.fnl
local function optional_require(modname)
  local ok,mod = pcall(require, modname)
  if ok then
    return mod
  else
    local function _1_(_, k)
      local function _2_()
        return error((modname .. " not available - called '" .. k .. "'"), 2)
      end
      return _2_
    end
    return setmetatable({}, {__index = _1_})
  end
end
return {require = optional_require}
