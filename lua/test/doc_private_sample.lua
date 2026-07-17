-- test/doc_private_sample.lua - Private documentation fixture
-- <jed@nelson.ac> // 2026-06-11

--- Private module used to test documentation visibility.
---@private
local M = {}

--- Return a fixture value.
---@return boolean value
function M.hidden()
    return true
end

return M
