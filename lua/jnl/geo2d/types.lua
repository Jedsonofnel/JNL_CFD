-- geo2d/types.lua - type stubs for geo2d UD types
-- <jed@nelson.ac> // 2026-06-10

---@meta

---@alias Point2D [number, number]
---@alias Curve2DKind "line"|"arc"|"polyline"|"chain"
---@alias Dist1DKind "uniform"|"cosine_both"|"geom_start"|"geom_end"
---@alias Curve2DSampleMode "arclen"|"param"

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

---@class Dist1D
local Dist1D = {}

---Return the distribution kind.
---@return Dist1DKind
function Dist1D:kind() end

---Evaluate the normalised coordinate for zero-based point index i out of n points.
---@param i integer
---@param n integer
---@return number
function Dist1D:eval(i, n) end

---@class Curve2D
local Curve2D = {}

---Return the curve kind.
---@return Curve2DKind
function Curve2D:kind() end

---Return an independent deep clone.
---@return Curve2D
function Curve2D:clone() end

---Return an independent curve with reversed orientation.
---@return Curve2D
function Curve2D:reversed() end

---Reverse this curve in place and return it.
---@return self
function Curve2D:reverse_inplace() end

---Return the total curve length.
---@return number
function Curve2D:length() end

---Return the first point in the current orientation.
---@return Point2D
function Curve2D:start() end

---Return the final point in the current orientation.
---@return Point2D
function Curve2D:finish() end

---Evaluate using the curve's native parameterisation.
---@param t number Normalised parameter in [0, 1].
---@return Point2D
function Curve2D:eval(t) end

---Evaluate using normalised arc length.
---@param s number Normalised arc length in [0, 1].
---@return Point2D
function Curve2D:eval_arclen(s) end

---Sample points from the curve.
---@param n integer
---@param distribution Dist1D?
---@param mode Curve2DSampleMode?
---@return Point2D[]
function Curve2D:sample(n, distribution, mode) end

---@class BoundingBox
---@field min_x number
---@field min_y number
---@field max_x number
---@field max_y number

---@class Domain2DSampleResult
---@field pts    Point2D[]
---@field marker integer
---@field name   string

---@class Domain2D
---@field _reg MarkerRegistry? Marker registry attached by `domain.from_pen`.
local Domain2D = {}

-- Construction (all return self for chaining)

---Add a named boundary patch (a sub-curve of the outer boundary).
---@param name   string
---@param curve  Curve2D
---@return self
function Domain2D:add_patch(name, curve) end

---Add a closed interior hole.
---`seed` must be a point strictly inside the hole (used to suppress interior cells).
---@param name     string?
---@param boundary Curve2D  Must be a closed curve.
---@param seed     Point2D  Interior point.
---@return self
function Domain2D:add_hole(name, boundary, seed) end

---Add a region seed for cell-region labelling and per-region area constraints.
---@param name     string
---@param seed     Point2D
---@param max_area number?  Area constraint; `<= 0` means unconstrained.
---@return self
function Domain2D:add_region(name, seed, max_area) end

---Set the marker applied to unpatched outer boundary edges.
---@param marker integer
---@return self
function Domain2D:set_default_marker(marker) end

-- Validation

---Validate the domain. Returns `true` on success, or `nil, message` on failure.
---@return true?
---@return string? err
function Domain2D:check() end

-- Queries

---True if `point` is strictly inside the outer boundary and outside all holes.
---@param point    Point2D
---@param sample_n integer?  Sample resolution (default 128).
---@return boolean
function Domain2D:contains(point, sample_n) end

---True if any segment of `curve` intersects any domain boundary.
---@param curve    Curve2D
---@param sample_n integer?  Sample resolution (default 128).
---@return boolean
function Domain2D:curve_intersects_boundary(curve, sample_n) end

---True if the outer boundary self-intersects at the given resolution.
---@param sample_n integer?  Default 128.
---@return boolean
function Domain2D:outer_self_intersects(sample_n) end

---True if holes `i` and `j` have intersecting boundaries.
---@param i        integer  1-based hole index.
---@param j        integer  1-based hole index.
---@param sample_n integer?  Default 128.
---@return boolean
function Domain2D:holes_intersect(i, j, sample_n) end

-- Geometry

---Return the bounding box of the outer boundary (approximate).
---@return BoundingBox
function Domain2D:bbox() end

-- Sampling

---Sample the outer boundary at `n` arc-length-distributed points.
---@param n integer
---@return Point2D[]
function Domain2D:sample_outer(n) end

---Sample hole `i` (1-based) at `n` arc-length-distributed points.
---@param i integer  1-based hole index.
---@param n integer
---@return Point2D[]
function Domain2D:sample_hole(i, n) end

---Sample all boundaries.
---
---Result layout: `[1]` outer boundary, `[2..n_holes+1]` holes, `[n_holes+2..]` patches.
---@param n integer
---@return Domain2DSampleResult[]
function Domain2D:sample_all(n) end

-- Accessors

---@return integer
function Domain2D:n_patches() end

---@return integer
function Domain2D:n_holes() end

---@return integer
function Domain2D:n_regions() end
