-- lua/jnl/mesh2d/types.lua - LuaLS stubs for mesh2d userdata types
-- <jed@nelson.ac> // 2026-06-12

---@meta

--
-- Shared types
--

--- A named boundary patch on a built mesh.
---@class MeshPatch
---@field name       string  Patch label.
---@field start_face integer 0-based index of the first face in this patch.
---@field n_faces    integer Number of faces in this patch.
---@field marker     integer Integer marker from the mesh generator.

--
-- Mesh2D (jnl.mesh2d_internal)
--

--- A built 2D finite-volume polymesh.
---@class Mesh2D
local Mesh2D = {}

--- Number of real (conservation-volume) cells.
---@return integer
function Mesh2D:n_cells() end

--- Total cell count including ghost cells.
---@return integer
function Mesh2D:n_total_cells() end

---@return integer
function Mesh2D:n_real_cells() end

---@return integer
function Mesh2D:n_ghost_cells() end

---@return integer
function Mesh2D:n_faces() end

---@return integer
function Mesh2D:n_internal_faces() end

---@return integer
function Mesh2D:n_boundary_faces() end

---@return integer
function Mesh2D:n_baffle_faces() end

---@return integer
function Mesh2D:n_patches() end

---@return MeshPatch[]
function Mesh2D:patches() end

---@param name string
---@return MeshPatch?
function Mesh2D:patch_by_name(name) end

--- Cell centre coordinates, 1-based.
---@param i integer
---@return number x
---@return number y
function Mesh2D:cell_centre(i) end

--- Cell area for cell i, 1-based.
---@param i integer
---@return number
function Mesh2D:cell_vol(i) end

--- Square root of mean cell area.
---@return number
function Mesh2D:mean_cell_size() end

--- Face centre coordinates, 1-based.
---@param i integer
---@return number x
---@return number y
function Mesh2D:face_centre(i) end

--- Face outward unit normal, 1-based.
---@param i integer
---@return number nx
---@return number ny
function Mesh2D:face_normal(i) end

--- Owner cell index for face f, 0-based.
---@param f integer 0-based face index.
---@return integer
function Mesh2D:face_owner0(f) end

--- Neighbour cell index for face f, 0-based.
---
--- For boundary and baffle faces the neighbour is a ghost cell;
--- no negative-marker encoding is used.
---@param f integer 0-based face index.
---@return integer
function Mesh2D:face_neighbour0(f) end

---@param f integer 0-based face index.
---@return number x
---@return number y
function Mesh2D:face_centre0(f) end

---@param f integer 0-based face index.
---@return number nx
---@return number ny
function Mesh2D:face_normal0(f) end

---@param f integer 0-based face index.
---@return number
function Mesh2D:face_area0(f) end

--- Borrowed slice of real-cell x-coordinates.  The mesh must remain alive.
---@return VecUD
function Mesh2D:cell_cx_vec() end

--- Borrowed slice of real-cell y-coordinates.  The mesh must remain alive.
---@return VecUD
function Mesh2D:cell_cy_vec() end

--- Borrowed slice of real-cell volumes.  The mesh must remain alive.
---@return VecUD
function Mesh2D:cell_vol_vec() end

--
-- Block (jnl.strucmesh2d_internal)
--

--- A raw structured grid block.
---
--- Boundary coordinates are populated by sample_edge and copy_edge.
--- Interior coordinates are filled by tfi() or smooth().
--- Call build() to lower to a Mesh2D, or add_block() to include in a Grid.
---@class Block
local Block = {}

--- Set the integer marker for a boundary edge.
---@param edge   integer Direction constant (SOUTH/EAST/NORTH/WEST).
---@param marker integer
function Block:set_edge_marker(edge, marker) end

---@param marker integer
function Block:set_region_marker(marker) end

--- Sample a curve onto an edge at the block's resolution.
---@param edge  integer Direction constant.
---@param curve Curve2D
---@param dist  Dist1D  Point distribution along the edge.
function Block:sample_edge(edge, curve, dist) end

--- Copy boundary coordinates from another block's edge to this edge.
---
--- Ensures exact coordinate agreement at shared boundaries.
--- The grid builder calls this automatically for declared joins.
---@param dst_edge integer
---@param src      Block
---@param src_edge integer
---@param reversed boolean?
function Block:copy_edge(dst_edge, src, src_edge, reversed) end

--- Fill interior coordinates by transfinite interpolation.
--- All four edges must be populated first.
function Block:tfi() end

--- Smooth interior coordinates with Laplacian relaxation.
---@param opts? { max_iter:integer?, omega:number?, tol:number? }
function Block:smooth(opts) end

--- Lower to a standalone Mesh2D.
---@return Mesh2D? mesh
---@return string?  err
function Block:build() end

--
-- Grid (jnl.strucmesh2d_internal)
--

--- A multi-block structured grid that lowers to a single Mesh2D.
---@class Grid
local Grid = {}

--- Add a block and return its integer ID for use in add_join.
---@param block Block
---@return integer id
function Grid:add_block(block) end

--- Register a topology join between two block edges.
---
--- The block with dst_edge must NOT have that edge sampled directly;
--- the grid builder will populate it via copy_edge before running TFI.
---@param id0      integer
---@param edge0    integer
---@param id1      integer
---@param edge1    integer
---@param reversed boolean?
function Grid:add_join(id0, edge0, id1, edge1, reversed) end

--- Validate join topology and geometry.
---@return boolean ok
---@return string  errmsg
function Grid:check() end

--- Lower the multi-block grid to a single Mesh2D.
---@return Mesh2D? mesh
---@return string?  err
function Grid:build() end

--
-- TriOpts (jnl.trimesh2d_internal)
--

--- Immutable Triangle quality options.  Each setter returns a new TriOpts.
---@class TriOpts
local TriOpts = {}

---@param angle number Minimum interior angle in degrees.
---@return TriOpts
function TriOpts:set_min_angle(angle) end

---@param area number Global maximum triangle area.
---@return TriOpts
function TriOpts:set_global_max_area(area) end

---@param enabled boolean
---@return TriOpts
function TriOpts:enable_region_areas(enabled) end

---@param enabled boolean
---@return TriOpts
function TriOpts:set_conforming_delaunay(enabled) end

---@param enabled boolean
---@return TriOpts
function TriOpts:set_quiet(enabled) end

--- Derive a global max area from a target cell count.
---@param pslg PSLG
---@param n    integer Target number of triangles.
---@return TriOpts
function TriOpts:set_cell_count(pslg, n) end

--- Derive a global max area from a target mean edge length.
---@param pslg PSLG
---@param res  number Target resolution.
---@return TriOpts
function TriOpts:set_resolution(pslg, res) end

--
-- TriTags (jnl.trimesh2d_internal)
--

--- Marker-to-name registry consumed by triangulate() to label mesh patches,
--- baffles, and regions.
---@class TriTags
local TriTags = {}

---@param marker integer
---@param name   string
---@return boolean ok
---@return string  errmsg
function TriTags:add_patch(marker, name) end

---@param marker integer
---@param name   string
---@return boolean ok
---@return string  errmsg
function TriTags:add_baffle(marker, name) end

---@param marker integer
---@param name   string
---@return boolean ok
---@return string  errmsg
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

--
-- TriSpec (jnl.trimesh2d_internal)
--

--- Combined triangulation specification: opts and tags in one object.
--- Preferred over TriOpts + TriTags separately.
---@class TriSpec
local TriSpec = {}

---@param opts TriOpts
function TriSpec:set_opts(opts) end

---@param marker integer
---@param name   string
---@return boolean ok
---@return string  errmsg
function TriSpec:add_patch(marker, name) end

---@param marker integer
---@param name   string
---@return boolean ok
---@return string  errmsg
function TriSpec:add_baffle(marker, name) end

---@param marker integer
---@param name   string
---@return boolean ok
---@return string  errmsg
function TriSpec:add_region(marker, name) end

return {}
