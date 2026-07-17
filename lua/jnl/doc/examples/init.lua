-- lua/jnl/doc/examples/init.lua - LLM example script registry
-- <jed@nelson.ac> // 2026-06-11

--- Provide complete JNL example scripts for generated LLM context.
local M = {}

local EXAMPLES = {
    -- {
    -- 	title = "FVM validation study (conv_diff.lua)",
    -- 	source = require("jnl.doc.examples.conv_diff"),
    -- },
    -- {
    -- 	title = "FVM Couette validation (couette.lua)",
    -- 	source = require("jnl.doc.examples.couette"),
    -- },
    -- {
    -- 	title = "FVM Poiseuille validation (poiseuille.lua)",
    -- 	source = require("jnl.doc.examples.poiseuille"),
    -- },
}

--- Return registered LLM examples in display order.
---@return table[] examples
function M.all()
    local examples = {}

    for _, example in ipairs(EXAMPLES) do
        examples[#examples + 1] = example
    end

    return examples
end

return M
