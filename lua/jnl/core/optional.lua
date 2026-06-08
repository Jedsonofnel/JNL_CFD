-- jnl/core/optional.lua
local M = {}

---Require a module, returning a deferred-error stub if unavailable.
---@param modname string
---@return table
function M.require(modname)
	local ok, mod = pcall(require, modname)
	if ok then return mod end
	return setmetatable({}, {
		__index = function(_, k)
			return function()
				error(modname .. " not available — called '" .. k .. "'", 2)
			end
		end,
	})
end

return M
