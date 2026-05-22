-- mesh2d/types.lua
---@meta

---@class MeshPatch
---@field name string
---@field start_face integer
---@field n_faces integer
---@field marker integer

---@class Mesh2D
local Mesh2D = {}

---Total number of cells.
---@return integer
function Mesh2D:n_cells() end

---Total number of faces (internal + boundary).
---@return integer
function Mesh2D:n_faces() end

---Number of internal faces (fluid-fluid interfaces).
---Used as n_conns when constructing an FvmCtx.
---@return integer
function Mesh2D:n_internal_faces() end

---Number of internal connections — equivalent to n_internal_faces.
---Provided explicitly so FvmCtx construction doesn't require knowing the convention.
---@return integer
function Mesh2D:n_conns() end

---Number of boundary patches.
---@return integer
function Mesh2D:n_patches() end

---Return all patches as an array of MeshPatch tables.
---@return MeshPatch[]
function Mesh2D:patches() end

---Find a patch by name, or nil if not found.
---@param name string
---@return MeshPatch?
function Mesh2D:patch_by_name(name) end

---Return the cell-centre coordinates for cell i (1-based).
---@param i integer
---@return number cx
---@return number cy
function Mesh2D:cell_centre(i) end

---Return the face-centre coordinates for face i (1-based).
---@param i integer
---@return number cx
---@return number cy
function Mesh2D:face_centre(i) end

---Return the cell volume (2D: area) for cell i (1-based).
---@param i integer
---@return number
function Mesh2D:cell_vol(i) end
