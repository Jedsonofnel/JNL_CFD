-- lua/jnl/repl/init.lua - Public REPL interface for the JNL suite
-- <jed@nelson.ac> // 2026-06-12

local Core = require("jnl.repl.core")

--- Provide a configurable Fennel REPL with a convenient default instance.
local M = {}

local default_repl = nil

--- Return the process-wide default REPL, creating it when needed.
---@return jnl.repl.Repl repl
function M.default()
    if not default_repl then
        default_repl = Core.new()
    end

    return default_repl
end

--- Create an independent REPL instance.
---@param opts? table Construction options.
---@return jnl.repl.Repl repl
function M.new(opts)
    return Core.new(opts)
end

--- Expose a value as a global and register it with the default REPL help system.
---
--- With no documentation argument, JNL attempts to find a uniquely matching
--- source-derived API description. Pass literal text, `{ from = "module.symbol" }`,
--- or `false` to suppress documentation lookup.
---@param name string User-facing global name.
---@param value any Value to expose.
---@param doc? ReplDocSpec Documentation source.
---@return any value
function M.register(name, value, doc)
    return M.default():register(name, value, doc)
end

--- Register a comma command on the default REPL.
---@param name string Command name without the comma.
---@param fn fun(repl: jnl.repl.Repl, arg: string)
---@param usage? string Displayed command usage.
---@param doc? string Help text.
function M.command(name, fn, usage, doc)
    return M.default():command(name, fn, usage, doc)
end

--- Register study-specific usage on the default REPL.
---@param spec ReplUsageSpec Usage text or provider.
function M.usage(spec)
    return M.default():usage(spec)
end

--- Store a value in a named special on the default REPL.
---@param name string Name such as `*last-run*`.
---@param value any Value to store.
---@param label? string|false Confirmation label; false suppresses output.
---@return any value
function M.special(name, value, label)
    return M.default():special(name, value, label)
end

--- Pretty-print a value using the default REPL printer.
---@param value any Value to print.
---@param opts? table Fennel view options.
---@return any value
function M.pp(value, opts)
    return M.default():pp(value, opts)
end

--- Start the default REPL.
---
--- Calling this from a script marks the REPL as started in the host program, so
--- `--repl` does not start another REPL after the script returns.
function M.run()
    return M.default():run()
end

--- Return true when Ctrl-C has requested cancellation of active evaluation.
---@return boolean cancelled
function M.is_cancelled()
    return Core.is_cancelled()
end

--- Print globals introduced by a script.
---@param script_path string Executed script path.
function M.script_summary(script_path)
    return Core.script_summary(script_path)
end

--- Return the complete JNL coding context for a language model.
---@param opts? table Context rendering options.
---@return string text
function M.llm_string(opts)
    local llm = require("jnl.doc.llm")
    return llm.context_string(opts or {})
end

--- Print the complete JNL coding context for a language model.
---@param opts? table Context rendering options.
function M.llm(opts)
    io.write(M.llm_string(opts))
end

return M
