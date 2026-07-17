-- jnl/repl/completion.lua - Completion policy for the JNL REPL
-- <jed@nelson.ac> // 2026-06-12

--- Generate completion candidates for the active JNL REPL.
---@private
local M = {}

local FENNEL_FORMS = {
    ["and"] = true,
    ["case"] = true,
    ["collect"] = true,
    ["do"] = true,
    ["each"] = true,
    ["fn"] = true,
    ["for"] = true,
    ["if"] = true,
    ["lambda"] = true,
    ["let"] = true,
    ["local"] = true,
    ["match"] = true,
    ["not"] = true,
    ["or"] = true,
    ["require"] = true,
    ["set"] = true,
    ["values"] = true,
    ["when"] = true,
    ["while"] = true,
}

local function add_matching(out, seen, values, prefix)
    for name in pairs(values or {}) do
        if
            type(name) == "string"
            and name:sub(1, #prefix) == prefix
            and not seen[name]
        then
            seen[name] = true
            out[#out + 1] = name
        end
    end
end

--- Return candidates for one Readline completion request.
---@param repl jnl.repl.Repl Active REPL.
---@param context table Readline context.
---@return string[] matches
---@return table opts
function M.complete(repl, context)
    local text = context.text or ""
    local matches = {}
    local seen = {}

    if text:sub(1, 1) == "," then
        for name in pairs(repl.commands) do
            local candidate = "," .. name

            if candidate:sub(1, #text) == text then
                matches[#matches + 1] = candidate
            end
        end
    else
        add_matching(matches, seen, repl.registry, text)

        add_matching(matches, seen, _G, text)

        add_matching(matches, seen, FENNEL_FORMS, text)
    end

    table.sort(matches)

    return matches, {
        fallback = false,
        append = false,
    }
end

return M
