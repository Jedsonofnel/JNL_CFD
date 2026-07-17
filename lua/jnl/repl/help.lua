-- lua/jnl/repl/help.lua - REPL help and documentation lookup
-- <jed@nelson.ac> // 2026-06-12

local Printer = require("jnl.repl.printer")

--- Implement REPL help rendering and source documentation lookup.
---@private
local M = {}

local STDLIB = {
    _G = true,
    _VERSION = true,

    assert = true,
    collectgarbage = true,
    dofile = true,
    error = true,
    getmetatable = true,
    ipairs = true,
    load = true,
    loadfile = true,
    next = true,
    pairs = true,
    pcall = true,
    print = true,
    rawequal = true,
    rawget = true,
    rawlen = true,
    rawset = true,
    require = true,
    select = true,
    setmetatable = true,
    tonumber = true,
    tostring = true,
    type = true,
    warn = true,
    xpcall = true,

    coroutine = true,
    debug = true,
    io = true,
    math = true,
    os = true,
    package = true,
    string = true,
    table = true,
    utf8 = true,

    _script = true,
    readline = true,
    __jnl_repl_cancel_seen = true,
    __jnl_repl_cancel_clear = true,
    __jnl_repl_mark_started = true,
}

local function suffix_match(name, suffix)
    return name == suffix
        or name:sub(-#suffix - 1) == "." .. suffix
        or name:sub(-#suffix - 1) == ":" .. suffix
end

local function append_sorted_keys(out, values)
    for key in pairs(values) do
        out[#out + 1] = key
    end

    table.sort(out)
    return out
end

local function dedup_sorted(names)
    local seen = {}
    local out = {}

    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end

    table.sort(out)
    return out
end

local function printer_for(repl)
    return Printer.new({
        width = repl.help_width,
        out = function(text)
            io.write(text)
        end,
    })
end

local function module_is_public(raw, item)
    if not item.module then
        return true
    end

    local module = raw.modules[item.module]

    return module ~= nil and not module.private
end

local function find_item(raw, values, reference, include_private)
    local exact = values[reference]

    if exact and (include_private or module_is_public(raw, exact)) then
        return exact
    end

    local matches = {}

    for name, item in pairs(values) do
        if
            suffix_match(name, reference)
            and (include_private or module_is_public(raw, item))
        then
            matches[#matches + 1] = item
        end
    end

    if #matches == 1 then
        return matches[1]
    end

    return nil
end

local function lookup_doc(repl, reference, include_private)
    local docs = M.index(repl)
    local raw = docs.raw

    local symbol = find_item(raw, raw.symbols, reference, include_private)

    if symbol and symbol.doc and symbol.doc ~= "" then
        return symbol.doc
    end

    local type_doc = find_item(raw, raw.types, reference, include_private)

    if type_doc and type_doc.doc and type_doc.doc ~= "" then
        return type_doc.doc
    end

    local module = find_item(raw, raw.modules, reference, include_private)

    if
        module
        and module.doc
        and module.doc ~= ""
        and (include_private or not module.private)
    then
        return module.doc
    end

    return nil
end

--- Return the cached documentation index, optionally rebuilding it.
---@param repl jnl.repl.Repl
---@param refresh? boolean
---@return DocIndex index
function M.index(repl, refresh)
    if refresh then
        repl.doc_index = nil
    end

    if not repl.doc_index then
        local doc = require("jnl.doc")

        repl.doc_index = doc.scan({
            packages = { "jnl" },
        })
    end

    return repl.doc_index
end

--- Resolve registration help text from a literal or documentation lookup.
---@param repl jnl.repl.Repl
---@param name string Registered name.
---@param spec? ReplDocSpec
---@return string text
function M.registration_doc(repl, name, spec)
    if spec == false then
        return ""
    end

    if type(spec) == "string" then
        return spec
    end

    if type(spec) == "table" then
        if spec.doc ~= nil then
            return tostring(spec.doc)
        end

        if spec.lookup == false then
            return ""
        end

        if type(spec.from) == "string" then
            return lookup_doc(repl, spec.from, true) or ""
        end
    end

    return lookup_doc(repl, name, false) or ""
end

--- Return true when a name is a numbered Fennel result special.
---@param name any
---@return boolean result
function M.is_result_name(name)
    return type(name) == "string"
        and (name == "*_" or name:match("^%*%d+$") ~= nil)
end

--- Return true when a name has the JNL named-special form.
---@param name any
---@return boolean result
function M.is_special_name(name)
    return type(name) == "string"
        and name:match("^%*[%w%-_]+%*$") ~= nil
        and not M.is_result_name(name)
end

--- Capture the currently defined global names.
---@return table<string, boolean> globals
function M.capture_globals()
    local captured = {}

    for name in pairs(_G) do
        captured[name] = true
    end

    return captured
end

--- Return user-visible global and registered names.
---@param repl jnl.repl.Repl
---@return string[] names
function M.user_global_names(repl)
    local names = {}

    for name in pairs(_G) do
        if
            not STDLIB[name]
            and not M.is_result_name(name)
            and not M.is_special_name(name)
            and not repl.globals_at_start[name]
        then
            names[#names + 1] = name
        end
    end

    for name in pairs(repl.registry) do
        names[#names + 1] = name
    end

    return dedup_sorted(names)
end

--- Return globals suitable for a post-script summary.
---@return string[] names
function M.script_global_names()
    local names = {}

    for name in pairs(_G) do
        if
            not STDLIB[name]
            and not M.is_result_name(name)
            and not M.is_special_name(name)
        then
            names[#names + 1] = name
        end
    end

    table.sort(names)
    return names
end

--- Print user-defined globals and registered values.
---@param repl jnl.repl.Repl
function M.print_globals(repl)
    local names = M.user_global_names(repl)

    if #names == 0 then
        io.write("no user globals defined\n")
        return
    end

    local printer = printer_for(repl)

    for _, name in ipairs(names) do
        local entry = repl.registry[name]
        local doc = entry and entry.doc or ""

        if doc ~= "" then
            printer:columns(name, doc, {
                indent = "  ",
                left_width = 22,
            })
        else
            printer:line("  " .. name)
        end
    end
end

--- Print the main REPL help overview.
---@param repl jnl.repl.Repl
function M.print_overview(repl)
    local printer = printer_for(repl)

    printer:header("Comma commands", 2)

    for _, name in ipairs(append_sorted_keys({}, repl.commands)) do
        local command = repl.commands[name]

        printer:columns(command.usage, command.doc, {
            indent = "  ",
            left_width = 26,
        })
    end

    local names = append_sorted_keys({}, repl.registry)

    if #names > 0 then
        printer:header("Registered globals", 2)
        printer:line("Use ,help <name> for details.")
        printer:blank()

        for _, name in ipairs(names) do
            local entry = repl.registry[name]

            printer:columns(name, entry.doc, {
                indent = "  ",
                left_width = 24,
            })
        end
    end

    printer:header("REPL controls", 2)
    printer:bullet("Fennel results are available as *1, *2, and *3.")
    printer:bullet("Named specials may be stored as *name* with remember.")
    printer:bullet("Ctrl-C at the prompt clears the current line.")
    printer:bullet("Ctrl-C once requests cancellation; twice forces it.")
    printer:bullet("Ctrl-D or ,quit exits.")
end

--- Print help for one command or registered value.
---@param repl jnl.repl.Repl
---@param name string Help topic.
function M.print_topic(repl, name)
    local printer = printer_for(repl)

    if M.is_result_name(name) or M.is_special_name(name) then
        printer:line(string.format("no help for '%s'", name))
        return
    end

    local entry = repl.registry[name]

    if entry then
        printer:header(name, 2)

        if entry.doc ~= "" then
            printer:wrap("", "", entry.doc)
        else
            printer:line("(no documentation)")
        end

        printer:kv("type", type(entry.value))
        return
    end

    local command = repl.commands[name]

    if command then
        printer:header(command.usage, 2)
        printer:wrap("", "", command.doc)
        return
    end

    printer:line(string.format("no help for '%s'", name))
end

return M
