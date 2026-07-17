-- lua/flux/html.lua - HTML string DSL for the Flux web framework.
-- <jed@nelson.ac> // 2026-06-13

--- HTML string DSL for the Flux web framework.
---
--- Tag functions accept attrs and children using Lua call sugar.
--- Call grammar for any tag:
---
---   tag "string"              ->  <tag>string</tag>
---   tag("fmt %s", arg)        ->  <tag>fmt arg</tag>
---   tag { children }          ->  <tag>children</tag>
---   tag {attrs} "string"      ->  <tag attrs>string</tag>
---   tag {attrs} ("fmt", arg)  ->  <tag attrs>fmt arg</tag>
---   tag {attrs} { children }  ->  <tag attrs>children</tag>
---   tag {attrs}               ->  <tag attrs />
---
--- Obtain tag functions via env() to avoid manual local declarations:
---
---   local _ENV = require("flux.html").env()
---
---   div { class="container" } {
---     h1 "JNLCFD",
---     p  { class="lead" } "A Lua/C CFD framework.",
---   }
---
--- H.table refers to the HTML element. The Lua table library is unaffected
--- inside an env() scope.
local M = {}

--- HTML5 doctype declaration.
---@type string
M.doctype = "<!DOCTYPE html>"

--
-- Internal helpers
--

local VOID = {
    area = true,
    base = true,
    br = true,
    col = true,
    embed = true,
    hr = true,
    img = true,
    input = true,
    link = true,
    meta = true,
    param = true,
    source = true,
    track = true,
    wbr = true,
}

-- True when t has at least one string key, indicating it carries attrs.
local function has_attrs(t)
    for k in pairs(t) do
        if type(k) == "string" then
            return true
        end
    end
    return false
end

-- Recursively render a node to a string.
-- Accepts strings, numbers, raw sentinels, and integer-keyed child tables.
local function render(node)
    if node == nil then
        return ""
    end
    if type(node) == "number" then
        return tostring(node)
    end
    if type(node) == "string" then
        return node
    end
    if type(node) == "table" then
        if node.flux_raw then
            return node[1]
        end
        if node.flux_element then
            return tostring(node)
        end -- <-- add this
        local parts = {}
        for i = 1, #node do
            parts[i] = render(node[i])
        end
        return table.concat(parts)
    end
    return tostring(node)
end

-- Return s formatted with extra args when present, otherwise return s unchanged.
local function maybe_fmt(s, ...)
    if select("#", ...) == 0 then
        return s
    end
    return string.format(s, ...)
end

-- Serialise an attrs table to an HTML attribute string with a leading space.
-- nil and false values are skipped. true emits a bare attribute name.
-- Keys are sorted for deterministic output.
local function attrs_str(t)
    local parts = {}
    for k, v in pairs(t) do
        if type(k) == "string" and v ~= nil and v ~= false then
            if v == true then
                parts[#parts + 1] = k
            else
                parts[#parts + 1] = k .. '="' .. tostring(v) .. '"'
            end
        end
    end
    table.sort(parts)
    if #parts == 0 then
        return ""
    end
    return " " .. table.concat(parts, " ")
end

-- Return a tag function for the named HTML element.
local function el(tag)
    local is_void = VOID[tag]
    return function(first, ...)
        if first == nil then
            return is_void and "<" .. tag .. " />"
                or "<" .. tag .. "></" .. tag .. ">"
        end
        if type(first) == "string" then
            if is_void then
                return "<" .. tag .. " />"
            end
            return "<"
                .. tag
                .. ">"
                .. maybe_fmt(first, ...)
                .. "</"
                .. tag
                .. ">"
        end

        if type(first) == "table" then
            if not has_attrs(first) then
                if is_void then
                    return "<" .. tag .. " />"
                end
                return "<" .. tag .. ">" .. render(first) .. "</" .. tag .. ">"
            end
            local a = attrs_str(first)
            if is_void then
                return "<" .. tag .. a .. " />"
            end
            local open = "<" .. tag .. a .. ">"
            local close = "</" .. tag .. ">"
            local empty = open .. close

            -- Two-argument form: a({href="/"}, "text") or a({href="/"}, {"child"})
            local nargs = select("#", ...)
            if nargs > 0 then
                local children = ...
                local inner = type(children) == "string"
                        and maybe_fmt(children, select(2, ...))
                    or render(children)
                return open .. inner .. close
            end

            return setmetatable({ flux_element = true }, {
                __tostring = function()
                    return empty
                end,
                __call = function(_, children, ...)
                    if children == nil then
                        return empty
                    end
                    local inner = type(children) == "string"
                            and maybe_fmt(children, ...)
                        or render(children)
                    return open .. inner .. close
                end,
            })
        end

        return "<" .. tag .. ">" .. tostring(first) .. "</" .. tag .. ">"
    end
end

local tag_cache = {}

local function get_tag(name)
    if not tag_cache[name] then
        tag_cache[name] = el(name)
    end
    return tag_cache[name]
end

-- Tag functions are generated on first access and cached.
setmetatable(M, {
    __index = function(_, k)
        return get_tag(k)
    end,
})

--
-- Public helpers
--

--- Mark a string as pre-rendered HTML, bypassing any escaping.
--- Use for markdown output and other trusted HTML strings.
---@param s string|number
---@return table
function M.raw(s)
    return { flux_raw = true, tostring(s) }
end

--- Render content only when cond is truthy.
--- content may be a node or a zero-argument function returning a node,
--- which is useful for deferring construction of expensive subtrees.
---@param cond any
---@param content string|table|fun(): string|table
---@return string
function M.when(cond, content)
    if not cond then
        return ""
    end
    if type(content) == "function" then
        return render(content())
    end
    return render(content)
end

--- Map fn over array t and concatenate the rendered results.
---@param t table
---@param fn fun(v: any, i: integer): string|table
---@return string
function M.map(t, fn)
    local parts = {}
    for i, v in ipairs(t) do
        parts[#parts + 1] = render(fn(v, i))
    end
    return table.concat(parts)
end

--- Build a class attribute string from strings and conditional tables.
---
---   cls("btn", { active=is_active, disabled=false })  ->  "btn active"
---
--- String arguments are included unconditionally. Table keys whose values
--- are truthy are included; keys are sorted for deterministic output.
---@param ... string|table
---@return string
function M.cls(...)
    local parts = {}
    for _, v in ipairs({ ... }) do
        if type(v) == "string" and v ~= "" then
            parts[#parts + 1] = v
        elseif type(v) == "table" then
            local conds = {}
            for name, ok in pairs(v) do
                if ok then
                    conds[#conds + 1] = name
                end
            end
            table.sort(conds)
            for _, name in ipairs(conds) do
                parts[#parts + 1] = name
            end
        end
    end
    return table.concat(parts, " ")
end

--- Concatenate multiple nodes without a wrapper element.
--- Useful for HTMX responses returning sibling fragments.
---@param ... string|table
---@return string
function M.fragment(...)
    local args = { ... }
    local parts = {}
    for i = 1, #args do
        parts[i] = render(args[i])
    end
    return table.concat(parts)
end

--
-- Environment injection
--

--- Return a table suitable for use as _ENV in a module.
---
--- All HTML tag functions are accessible as bare names. Standard Lua globals
--- fall through via _G. The Lua table library is preserved under its normal
--- name; use H.table explicitly when the HTML element is needed. The helpers
--- raw, when, map, cls, frag, and F are included by default.
---
--- Optional extra entries are merged in before the fallback metamethod:
---
---   local _ENV = require("flux.html").env {
---     docs = require "web.lib.docs",
---   }
---@param extra? table
---@return table
function M.env(extra)
    local env = {
        -- Preserve the Lua table library; H.table gives the HTML element.
        table = table,
        raw = M.raw,
        when = M.when,
        map = M.map,
        cls = M.cls,
        frag = M.fragment,
        F = string.format,
        doctype = M.doctype,
    }
    if extra then
        for k, v in pairs(extra) do
            env[k] = v
        end
    end
    return setmetatable(env, {
        __index = function(_, k)
            return _G[k] or M[k]
        end,
    })
end

--- Render a node tree (string, table of nodes, or flux element) to a string.
--- Use this to convert DSL output to a string before passing to H.raw().
---@param node any
---@return string
M.render = function(node)
    return render(node)
end

return M
