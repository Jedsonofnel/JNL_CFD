-- lua/jnl/mesh2d/init.lua - 2D mesh utilities
-- <jed@nelson.ac> // 2026-06-12

local B = require("jnl.mesh2d.block")

local M = {}

M.edges = require("jnl.mesh2d.edges")
M.cart = require("jnl.mesh2d.cartesian")
M.tri = require("jnl.mesh2d.tri")
M.block = B.block
M.grid = B.grid

--
-- Helpers
--

--- A normalised patch record returned by patch_list.
---@class PatchInfo
---@field id      integer Integer marker.
---@field name    string  Patch label.
---@field n_faces integer Number of boundary faces in this patch.

--- Return a normalised list of patches from a mesh.
---
--- Each entry renames `marker` to `id` for consistency with BC tables.
---@param mesh Mesh2D
---@return PatchInfo[]
function M.patch_list(mesh)
    local result = {}
    for _, p in ipairs(mesh:patches()) do
        result[#result + 1] = {
            id = p.marker,
            name = p.name,
            n_faces = p.n_faces,
        }
    end
    return result
end

--- Return a table indexed by both integer marker and name string.
---
--- Allows lookup by either `t[marker]` or `t["name"]`.
---@param mesh Mesh2D
---@return table<integer|string, PatchInfo>
function M.patch_lookup(mesh)
    local t = {}
    for _, p in ipairs(M.patch_list(mesh)) do
        t[p.id] = p
        t[p.name] = p
    end
    return t
end

--- Return a set of patch name strings present in the mesh.
---@param mesh Mesh2D
---@return table<string, true>
function M.patch_name_set(mesh)
    local s = {}
    for _, p in ipairs(mesh:patches()) do
        s[p.name] = true
    end
    return s
end

--- Return an ordered list of patch name strings.
---@param mesh Mesh2D
---@return string[]
function M.patch_name_list(mesh)
    local names = {}
    for _, p in ipairs(mesh:patches()) do
        names[#names + 1] = p.name
    end
    return names
end

return M
