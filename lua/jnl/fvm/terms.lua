-- jnl/fvm/terms.lua
-- <jed@nelson.ac> // 2026-07-16

-- deps
local nb = require("jnl.nabla")

--
-- Term types
--

---@class Term
---@field coeff Node?
---@operator unm:Term
local Term = {}
Term.__index = Term

---@class TermList
local TermList = {}
TermList.__index = TermList

--
-- Term constructors
--

local function laplacian(...)
    local coeff = nb.multiply(...)
    return setmetatable({ kind = "laplacian", coeff = coeff }, Term)
end

--
-- Termlist constructors
--

--- Creates a new termlist, implicitly adding terms together
---@param ... Term[]
---@return TermList
local function new_termlist(...)
    return setmetatable(..., TermList)
end

--
-- Term metamethods
--

function Term:negate()
    return setmetatable({ coeff = -self.coeff }, Term)
end

function Term:__unm()
    return setmetatable({ coeff = -self.coeff }, Term)
end

return {
    Term = Term,
    TermList = TermList,
    new_termlist = new_termlist,
    laplacian = laplacian,
}
