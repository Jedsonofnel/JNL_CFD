-- geo2d/curve.lua - composable parameterised 2D curves
-- <jed@nelson.ac> // 2026-06-10

local opt = require("jnl.core.optional")
local I = opt.require("jnl.curve2d_internal")

--- Low-level 2D curve primitives, transformations, and sampling utilities.
---
--- Curve2D objects are immutable value types produced by constructors and
--- transformations here, or retrieved from a Pen via :get() and :build().
---
--- For constructing domain boundaries with named patches, prefer the Pen API
--- (jnl.geo2d.pen).  Use this module for:
---   - simple standalone shapes (circle, rectangle) used as hole boundaries;
---   - post-construction transformations (translate, scale, rotate, map);
---   - sampling points for analysis or comparison;
---   - discretising curves onto a PSLG for custom meshing.
local M = {}

--
-- Raw primitives
--

---@type fun(x0:number, y0:number, x1:number, y1:number): Curve2D
M.line = I.line

---@type fun(cx:number, cy:number, radius:number, theta0:number, theta1:number): Curve2D
M.arc = I.arc

---@type fun(points:Point2D[]): Curve2D
M.polyline = I.polyline

---@type fun(curves:Curve2D[]): Curve2D
M.chain = I.chain

---@type fun(): Dist1D
M.uniform = I.uniform

---@type fun(): Dist1D
M.cosine_both = I.cosine_both

---@type fun(ratio:number): Dist1D
M.geom_start = I.geom_start

---@type fun(ratio:number): Dist1D
M.geom_end = I.geom_end

--
-- Helpers
--

local TAU = 2.0 * math.pi

---@param p Point2D
---@return number, number
local function unpack_point(p)
	assert(type(p) == "table" and #p >= 2, "expected point {x, y}")
	return p[1], p[2]
end

---@param points Point2D[]
---@return Point2D[]
local function copy_points(points)
	local out = {}
	for i, p in ipairs(points) do
		out[i] = { p[1], p[2] }
	end
	return out
end

---@param points Point2D[]
---@param eps number?
---@return boolean
local function points_closed(points, eps)
	eps = eps or 1e-10
	if #points < 2 then return false end

	local a = points[1]
	local b = points[#points]
	local dx = a[1] - b[1]
	local dy = a[2] - b[2]

	return dx * dx + dy * dy <= eps * eps
end

--
-- Convenience constructors
--

---Construct a line from two point tables.
---@param p0 Point2D
---@param p1 Point2D
---@return Curve2D
function M.between(p0, p1)
	local x0, y0 = unpack_point(p0)
	local x1, y1 = unpack_point(p1)
	return I.line(x0, y0, x1, y1)
end

---Construct a circular arc from point-like centre and angular limits.
---@param centre Point2D
---@param radius number
---@param theta0 number
---@param theta1 number
---@return Curve2D
function M.circular_arc(centre, radius, theta0, theta1)
	local cx, cy = unpack_point(centre)
	return I.arc(cx, cy, radius, theta0, theta1)
end

---Construct a complete circle as a chain of four exact arcs.
---
---The seam is at angle0 and the orientation is counter-clockwise unless
---clockwise is true.
---@param centre Point2D
---@param radius number
---@param opts? { angle0:number?, clockwise:boolean? }
---@return Curve2D
function M.circle(centre, radius, opts)
	opts = opts or {}

	local cx, cy = unpack_point(centre)
	local a0 = opts.angle0 or 0.0
	local da = (opts.clockwise and -1 or 1) * TAU / 4.0

	local arcs = {}
	for i = 0, 3 do
		arcs[i + 1] = I.arc(
			cx,
			cy,
			radius,
			a0 + i * da,
			a0 + (i + 1) * da
		)
	end

	return I.chain(arcs)
end

---Construct a rectangular closed boundary as a curve chain.
---
---The resulting orientation is counter-clockwise.
---@param x0 number
---@param y0 number
---@param x1 number
---@param y1 number
---@return Curve2D
function M.rectangle(x0, y0, x1, y1)
	if x0 > x1 then x0, x1 = x1, x0 end
	if y0 > y1 then y0, y1 = y1, y0 end

	return I.chain({
		I.line(x0, y0, x1, y0),
		I.line(x1, y0, x1, y1),
		I.line(x1, y1, x0, y1),
		I.line(x0, y1, x0, y0),
	})
end

---Construct an open polyline from points.
---@param points Point2D[]
---@return Curve2D
function M.through(points)
	assert(type(points) == "table" and #points >= 2,
		"through requires at least two points")
	return I.polyline(points)
end

---Construct a closed polyline.
---
---The first point is appended when it is not already repeated at the end.
---@param points Point2D[]
---@param eps number?
---@return Curve2D
function M.closed_polyline(points, eps)
	assert(type(points) == "table" and #points >= 3,
		"closed_polyline requires at least three points")

	local closed = copy_points(points)
	if not points_closed(closed, eps) then
		closed[#closed + 1] = { closed[1][1], closed[1][2] }
	end

	return I.polyline(closed)
end

---Construct a chain after removing nil entries.
---@param curves (Curve2D|nil)[]
---@return Curve2D
function M.join(curves)
	local parts = {}

	for _, c in ipairs(curves) do
		if c ~= nil then parts[#parts + 1] = c end
	end

	assert(#parts > 0, "join requires at least one curve")
	if #parts == 1 then return parts[1]:clone() end

	return I.chain(parts)
end

--
-- Sampled transformations
--
-- These deliberately lower to a polyline. Exact transformed curve kinds can
-- be added later if they become valuable.
--

---@param curve Curve2D
---@param fn fun(x:number, y:number): number, number
---@param opts? { n:integer?, distribution:Dist1D?, mode:Curve2DSampleMode? }
---@return Curve2D
function M.map(curve, fn, opts)
	opts = opts or {}

	local n = opts.n or 129
	local pts = curve:sample(
		n,
		opts.distribution or I.uniform(),
		opts.mode or "arclen"
	)

	for i, p in ipairs(pts) do
		local x, y = fn(p[1], p[2])
		pts[i] = { x, y }
	end

	return I.polyline(pts)
end

---@param curve Curve2D
---@param dx number
---@param dy number
---@param opts? table
---@return Curve2D
function M.translate(curve, dx, dy, opts)
	return M.map(curve, function(x, y)
		return x + dx, y + dy
	end, opts)
end

---@param curve Curve2D
---@param sx number
---@param sy number?
---@param opts? table
---@return Curve2D
function M.scale(curve, sx, sy, opts)
	sy = sy or sx

	return M.map(curve, function(x, y)
		return sx * x, sy * y
	end, opts)
end

---@param curve Curve2D
---@param angle number
---@param centre Point2D?
---@param opts? table
---@return Curve2D
function M.rotate(curve, angle, centre, opts)
	centre = centre or { 0.0, 0.0 }

	local cx, cy = unpack_point(centre)
	local c = math.cos(angle)
	local s = math.sin(angle)

	return M.map(curve, function(x, y)
		x, y = x - cx, y - cy
		return cx + c * x - s * y,
			cy + s * x + c * y
	end, opts)
end

--
-- Sampling helpers
--

---Sample a curve using arc-length parameterisation by default.
---@param curve Curve2D
---@param n integer
---@param distribution Dist1D?
---@return Point2D[]
function M.sample(curve, n, distribution)
	return curve:sample(n, distribution or I.uniform(), "arclen")
end

---Sample a closed curve without repeating the final seam point.
---@param curve Curve2D
---@param n integer
---@param distribution Dist1D?
---@return Point2D[]
function M.sample_closed(curve, n, distribution)
	assert(n >= 3, "sample_closed requires at least three points")

	local pts = curve:sample(n + 1, distribution or I.uniform(), "arclen")
	pts[#pts] = nil
	return pts
end

--
-- PSLG bridge
--

---Discretise an open curve onto a PSLG.
---@param curve Curve2D
---@param pslg PSLG
---@param marker integer?
---@param opts? { n:integer?, distribution:Dist1D?, closed:boolean?, eps:number? }
---@return integer[] nodes
function M.discretise_onto(curve, pslg, marker, opts)
	opts = opts or {}
	marker = marker or 0

	local n = opts.n or 65
	local closed = opts.closed or false
	local points

	if closed then
		points = M.sample_closed(curve, n, opts.distribution)
	else
		points = M.sample(curve, n, opts.distribution)
	end

	local nodes = {}
	for i, p in ipairs(points) do
		nodes[i] = pslg:node_find_or_add(
			p[1],
			p[2],
			0,
			opts.eps or 1e-10
		)
	end

	for i = 1, #nodes - 1 do
		pslg:edge_add(nodes[i], nodes[i + 1], marker)
	end

	if closed then
		pslg:edge_add(nodes[#nodes], nodes[1], marker)
	end

	return nodes
end

---Discretise a curve into a new PSLG.
---@param curve Curve2D
---@param marker integer?
---@param opts? table
---@return PSLG
function M.discretise(curve, marker, opts)
	---@type { pslg_new: fun(): PSLG }
	local pslg2d = require("jnl.pslg2d_internal")

	local g = pslg2d.pslg_new()
	M.discretise_onto(curve, g, marker, opts)
	return g
end

return M
