-- geo2d/types.lua - type stubs for geo2d_internal PSLG userdata
-- <jed@nelson.ac> // 2026-05-21

local M = {}

M._doc = "Type stubs for userdata exposed by geo2d_internal"

M._types = {
	PSLG = {
		doc         = "Planar Straight-Line Graph; nodes, constrained edges, holes, and regions",
		constructor = nil,
		methods     = {
			node_add          = { args = "x, y:number, marker:int?", ret = "int", doc = "Add a node; returns its index" },
			node_get          = { args = "idx:int", ret = "number?, number?", doc = "Coordinates of node at idx, or nil" },
			node_find_nearest = { args = "x, y:number", ret = "int?", doc = "Index of nearest node, or nil if empty" },
			node_find_or_add  = { args = "x, y:number, marker?, eps?", ret = "int", doc = "Find node within eps or add it" },
			edge_add          = { args = "p, q:int, marker:int?", ret = "int", doc = "Add constrained edge between two node indices" },
			hole_add          = { args = "x, y:number", ret = "int", doc = "Add a hole seed point" },
			region_add        = { args = "x, y:number, marker?, max_area?", ret = "int", doc = "Add a region seed with optional area constraint" },
			bbox              = { args = "", ret = "min_x, min_y, max_x, max_y", doc = "Bounding box as four numbers" },
			node_count        = { args = "", ret = "int", doc = "Current node count" },
			edge_count        = { args = "", ret = "int", doc = "Current edge count" },
		},
	},
}

---@meta

---@class PSLG
local PSLG = {}

---Add a node and return its index.
---@param x number
---@param y number
---@param marker integer?
---@return integer
function PSLG:node_add(x, y, marker) end

---Retrieve a node's coordinates by index, or nil if out of bounds.
---@param idx integer
---@return number?, number?
function PSLG:node_get(idx) end

---Find the nearest node to a point, or nil if empty.
---@param x number
---@param y number
---@return integer?
function PSLG:node_find_nearest(x, y) end

---Find a node within eps of the point, or add it.
---@param x number
---@param y number
---@param marker integer?
---@param eps number?
---@return integer
function PSLG:node_find_or_add(x, y, marker, eps) end

---Add a constrained edge between two node indices.
---@param p integer
---@param q integer
---@param marker integer?
---@return integer
function PSLG:edge_add(p, q, marker) end

---Add a hole seed point.
---@param x number
---@param y number
---@return integer
function PSLG:hole_add(x, y) end

---Add a region seed point with optional area constraint.
---@param x number
---@param y number
---@param marker integer?
---@param max_area number?
---@return integer
function PSLG:region_add(x, y, marker, max_area) end

---Return the bounding box as four numbers.
---@return number min_x
---@return number min_y
---@return number max_x
---@return number max_y
function PSLG:bbox() end

---Return the current node count.
---@return integer
function PSLG:node_count() end

---Return the current edge count.
---@return integer
function PSLG:edge_count() end

return M
