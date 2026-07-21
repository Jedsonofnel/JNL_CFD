-- lua/jnl/repl/command.lua - Built-in JNL REPL commands and values
-- <jed@nelson.ac> // 2026-06-12

local Help = require("jnl.repl.help")

--- Install built-in values and comma commands into a JNL REPL.
---@private
local M = {}

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function install_values(repl)
    repl:register("pp", function(value, opts)
        return repl:pp(value, opts)
    end, "Pretty-print a Lua or Fennel value: (pp value)")

    repl:register("remember", function(name, value, label)
        return repl:special(name, value, label)
    end, "Store a named REPL special: " .. '(remember "*last-run*" result)')
end

local function install_usage_command(repl)
    repl:command("usage", function(active)
        active:print_usage()
    end, ",usage", "Show study-specific workflow, entry points, and options")
end

local function install_quit_command(repl)
    repl:command("quit", function(active)
        io.write("bye\n")
        active:stop()
    end, ",quit", "Exit the REPL")
end

local function install_help_command(repl)
    repl:command(
        "help",
        function(active, argument)
            argument = trim(argument)

            if argument == "" then
                Help.print_overview(active)
            else
                Help.print_topic(active, argument)
            end
        end,
        ",help [topic]",
        "Show help, or show details for a command or registered value"
    )
end

local function install_globals_command(repl)
    repl:command("globals", function(active)
        Help.print_globals(active)
    end, ",globals", "List user-defined globals and registered values")
end

local function install_llm_command(repl)
    repl:command(
        "llm",
        function(active)
            local llm = require("jnl.doc.llm")

            io.write(llm.context_string({
                width = active.help_width,
            }))
        end,
        ",llm",
        "Print JNL coding instructions, examples, and API documentation"
    )
end

--- Install the standard REPL commands and registered values.
---@param repl jnl.repl.Repl REPL instance to configure.
function M.install(repl)
    install_values(repl)
    install_usage_command(repl)
    install_quit_command(repl)
    install_help_command(repl)
    install_globals_command(repl)
    install_llm_command(repl)
end

return M
