-- lua/jnl/mesh2d/types.lua - type stubs for mesh2d_internal userdata
-- <jed@nelson.ac> // 2026-05-25

local M = {}

---@meta

---@class TriOpts
local TriOpts = {}
---@return TriOpts
function TriOpts:set_min_angle(angle) end

---@return TriOpts
function TriOpts:set_global_max_area(area) end

---@return TriOpts
function TriOpts:enable_region_areas(enabled) end

---@return TriOpts
function TriOpts:set_conforming_delaunay(enabled) end

---@return TriOpts
function TriOpts:set_quiet(enabled) end

---@param pslg PSLG
---@param n integer
---@return TriOpts
function TriOpts:set_cell_count(pslg, n) end

---@param pslg PSLG
---@param res number
---@return TriOpts
function TriOpts:set_resolution(pslg, res) end

---@class TriTags
local TriTags = {}
---@param marker integer
---@param name string
---@return boolean, string
function TriTags:add_patch(marker, name) end

---@param marker integer
---@param name string
---@return boolean, string
function TriTags:add_baffle(marker, name) end

---@param marker integer
---@param name string
---@return boolean, string
function TriTags:add_region(marker, name) end

---@param marker integer
---@return string?
function TriTags:find_patch(marker) end

---@param marker integer
---@return string?
function TriTags:find_baffle(marker) end

---@param marker integer
---@return string?
function TriTags:find_region(marker) end

---@param enabled boolean
function TriTags:set_require_named_patches(enabled) end

---@param enabled boolean
function TriTags:set_require_named_baffles(enabled) end

---@param enabled boolean
function TriTags:set_require_named_regions(enabled) end

---@class TriSpec
local TriSpec = {}
---@param opts TriOpts
function TriSpec:set_opts(opts) end

---@param marker integer
---@param name string
---@return boolean, string
function TriSpec:add_patch(marker, name) end

---@param marker integer
---@param name string
---@return boolean, string
function TriSpec:add_baffle(marker, name) end

---@param marker integer
---@param name string
---@return boolean, string
function TriSpec:add_region(marker, name) end

---@param enabled boolean
function TriSpec:set_require_named_patches(enabled) end

---@param enabled boolean
function TriSpec:set_require_named_baffles(enabled) end

---@param enabled boolean
function TriSpec:set_require_named_regions(enabled) end

---@class MeshPatch
---@field name string
---@field start_face integer 0-based global face index
---@field n_faces integer
---@field marker integer

---@class Mesh2D
local Mesh = {}
---@return integer
function Mesh:n_cells() end

---@return integer
function Mesh:n_faces() end

---@return integer
function Mesh:n_internal_faces() end

---@return integer
function Mesh:n_patches() end

---@return MeshPatch[]
function Mesh:patches() end

---@param name string
---@return MeshPatch?
function Mesh:patch_by_name(name) end

---@param i integer
---@return number, number
function Mesh:cell_centre(i) end

---@param i integer
---@return number
function Mesh:cell_vol(i) end

---@return number
function Mesh:mean_cell_size() end

---@param i integer
---@return number, number
function Mesh:face_centre(i) end

---@param i integer
---@return number, number
function Mesh:face_normal(i) end

---@param f integer 0-based face index
---@return integer owner 0-based cell index
function Mesh:face_owner0(f) end

---@param f integer 0-based face index
---@return integer neighbour 0-based cell index, or encoded negative patch marker for boundary faces
function Mesh:face_neighbour0(f) end

---@param f integer 0-based face index
---@return number, number
function Mesh:face_centre0(f) end

---@param f integer 0-based face index
---@return number, number
function Mesh:face_normal0(f) end

---@param f integer 0-based face index
---@return number
function Mesh:face_area0(f) end

---@return VecUD
function Mesh:cell_cx_vec() end

---@return VecUD
function Mesh:cell_cy_vec() end

---@return VecUD
function Mesh:cell_vol_vec() end

return M
