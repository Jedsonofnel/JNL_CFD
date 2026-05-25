-- lua/jnl/mesh2d/types.lua - type stubs for mesh2d_internal userdata
-- <jed@nelson.ac> // 2026-05-25

local M = {}

M._doc = "Type stubs for userdata exposed by mesh2d_internal"
M._types = {
	TriOpts = {
		doc         = "Immutable triangulation options; all setters return a new TriOpts",
		constructor = "mesh2d_internal.opts_default()",
		methods     = {
			set_min_angle           = { args = "angle:number", ret = "TriOpts", doc = "Set minimum triangle angle (degrees); returns new opts" },
			set_global_max_area     = { args = "area:number", ret = "TriOpts", doc = "Set global maximum triangle area; returns new opts" },
			enable_region_areas     = { args = "enabled:bool", ret = "TriOpts", doc = "Enable per-region area constraints; returns new opts" },
			set_conforming_delaunay = { args = "enabled:bool", ret = "TriOpts", doc = "Enable conforming Delaunay mode; returns new opts" },
			set_quiet               = { args = "enabled:bool", ret = "TriOpts", doc = "Suppress Triangle.c output; returns new opts" },
			set_cell_count          = { args = "pslg:PSLG, n:int", ret = "TriOpts", doc = "Derive max_area from desired cell count; returns new opts" },
			set_resolution          = { args = "pslg:PSLG, res:number", ret = "TriOpts", doc = "Derive max_area from desired edge length; returns new opts" },
		},
	},
	TriTags = {
		doc         = "Mutable mapping from Triangle.c integer markers to named patches, baffles, and regions",
		constructor = "mesh2d_internal.tags_new()",
		methods     = {
			add_patch                 = { args = "marker:int, name:string", ret = "bool, string", doc = "Register a boundary patch marker; returns ok, errmsg" },
			add_baffle                = { args = "marker:int, name:string", ret = "bool, string", doc = "Register a baffle marker; returns ok, errmsg" },
			add_region                = { args = "marker:int, name:string", ret = "bool, string", doc = "Register a region marker; returns ok, errmsg" },
			find_patch                = { args = "marker:int", ret = "string?", doc = "Resolve patch name for marker, or nil" },
			find_baffle               = { args = "marker:int", ret = "string?", doc = "Resolve baffle name for marker, or nil" },
			find_region               = { args = "marker:int", ret = "string?", doc = "Resolve region name for marker, or nil" },
			set_require_named_patches = { args = "enabled:bool", ret = "nil", doc = "Error on unmapped patch markers during meshing" },
			set_require_named_baffles = { args = "enabled:bool", ret = "nil", doc = "Error on unmapped baffle markers during meshing" },
			set_require_named_regions = { args = "enabled:bool", ret = "nil", doc = "Error on unmapped region markers during meshing" },
		},
	},
	TriSpec = {
		doc         = "Combined opts + tags bundle passed to triangulate()",
		constructor = "mesh2d_internal.spec_new()",
		methods     = {
			set_opts                  = { args = "opts:TriOpts", ret = "nil", doc = "Copy opts into this spec" },
			add_patch                 = { args = "marker:int, name:string", ret = "bool, string", doc = "Delegate to embedded tags; returns ok, errmsg" },
			add_baffle                = { args = "marker:int, name:string", ret = "bool, string", doc = "Delegate to embedded tags; returns ok, errmsg" },
			add_region                = { args = "marker:int, name:string", ret = "bool, string", doc = "Delegate to embedded tags; returns ok, errmsg" },
			set_require_named_patches = { args = "enabled:bool", ret = "nil", doc = "Delegate to embedded tags" },
			set_require_named_baffles = { args = "enabled:bool", ret = "nil", doc = "Delegate to embedded tags" },
			set_require_named_regions = { args = "enabled:bool", ret = "nil", doc = "Delegate to embedded tags" },
		},
	},
	Mesh = {
		doc         = "Triangulated 2-D FVM mesh; owns topology, geometry, and patch data",
		constructor = "mesh2d_internal.triangulate(pslg, spec) or mesh2d.smesh_gen(w, h, nx, ny)",
		methods     = {
			n_cells          = { args = "", ret = "int", doc = "Total cell count" },
			n_faces          = { args = "", ret = "int", doc = "Total face count (internal + boundary)" },
			n_internal_faces = { args = "", ret = "int", doc = "Internal (non-boundary) face count" },
			n_patches        = { args = "", ret = "int", doc = "Boundary patch count" },
			patches          = { args = "", ret = "table", doc = "Array of {name, start_face, n_faces, marker} tables" },
			patch_by_name    = { args = "name:string", ret = "table?", doc = "Find patch descriptor by name, or nil" },
			cell_centre      = { args = "i:int", ret = "number, number", doc = "Centroid (cx, cy) of 1-based cell i" },
			cell_vol         = { args = "i:int", ret = "number", doc = "Area of 1-based cell i" },
			mean_cell_size   = { args = "", ret = "number", doc = "RMS cell size: sqrt(total_area / n_cells)" },
			face_centre      = { args = "i:int", ret = "number, number", doc = "Centroid (cx, cy) of 1-based face i" },
			face_normal      = { args = "i:int", ret = "number, number", doc = "Outward unit normal (nx, ny) of 1-based face i" },
			cell_cx_vec      = { args = "", ret = "vec", doc = "Bulk cell centroid x-coordinates as an owned vec" },
			cell_cy_vec      = { args = "", ret = "vec", doc = "Bulk cell centroid y-coordinates as an owned vec" },
			cell_vol_vec     = { args = "", ret = "vec", doc = "Bulk cell volumes/areas as an owned vec" },
		},
	},
}

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

---@class Mesh
local Mesh = {}
---@return integer
function Mesh:n_cells() end

---@return integer
function Mesh:n_faces() end

---@return integer
function Mesh:n_internal_faces() end

---@return integer
function Mesh:n_patches() end

---@return { name:string, start_face:integer, n_faces:integer, marker:integer }[]
function Mesh:patches() end

---@param name string
---@return { name:string, start_face:integer, n_faces:integer, marker:integer }?
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

---@return VecUD
function Mesh:cell_cx_vec() end

---@return VecUD
function Mesh:cell_cy_vec() end

---@return VecUD
function Mesh:cell_vol_vec() end

return M
