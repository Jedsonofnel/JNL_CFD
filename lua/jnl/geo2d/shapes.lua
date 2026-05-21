-- geo2d/shapes.lua - shapes library for 2D geometry
-- <jed@nelson.ac> // 2026-05-11

local geo2d = require("geo2d_internal")

local M = {}

--
-- Helpers
--

local function centroid(pts)
	local sx, sy = 0, 0
	for _, p in ipairs(pts) do
		sx = sx + p[1]
		sy = sy + p[2]
	end
	return sx / #pts, sy / #pts
end

local function point_in_polygon(pts, x, y)
	local inside = false
	local n = #pts
	local j = n
	for i = 1, n do
		local xi, yi = pts[i][1], pts[i][2]
		local xj, yj = pts[j][1], pts[j][2]
		if ((yi > y) ~= (yj > y)) and
			(x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function bbox_overlap(a, b)
	return a.max_x >= b.min_x and b.max_x >= a.min_x
		and a.max_y >= b.min_y and b.max_y >= a.min_y
end

local function edges_intersect(p1, p2, p3, p4)
	local d1x = p2[1] - p1[1]
	local d1y = p2[2] - p1[2]
	local d2x = p4[1] - p3[1]
	local d2y = p4[2] - p3[2]
	local cross = d1x * d2y - d1y * d2x
	if math.abs(cross) < 1e-12 then return false end -- parallel
	local dx = p3[1] - p1[1]
	local dy = p3[2] - p1[2]
	local t = (dx * d2y - dy * d2x) / cross
	local u = (dx * d1y - dy * d1x) / cross
	return t > 1e-10 and t < 1 - 1e-10
		and u > 1e-10 and u < 1 - 1e-10
end

local function poly_intersects(av, bv)
	local na, nb = #av, #bv
	for i = 1, na do
		for j = 1, nb do
			if edges_intersect(av[i], av[i % na + 1],
					bv[j], bv[j % nb + 1]) then
				return true
			end
		end
	end
	return false
end

--
-- Shape (bit of inheritence)
--

local Shape = {}
Shape.__index = Shape

function Shape:intersects(other)
	if not bbox_overlap(self:bbox(), other:bbox()) then
		return false
	end
	return poly_intersects(self:vertices(), other:vertices())
end

function Shape:discretise(marker, opts)
	local g = geo2d.pslg_new()
	self:discretise_onto(g, marker, opts)
	return g
end

--
-- Circle
--

local Circle = setmetatable({}, Shape)
Circle.__index = Circle

function M.circle(cx, cy, r, n)
	n = n or 64
	return setmetatable({
		cx = cx, cy = cy, r = r, n = n,
	}, Circle)
end

function Circle:bbox()
	return {
		min_x = self.cx - self.r,
		min_y = self.cy - self.r,
		max_x = self.cx + self.r,
		max_y = self.cy + self.r
	}
end

function Circle:centroid()
	return self.cx, self.cy
end

function Circle:contains(x, y)
	local dx, dy = x - self.cx, y - self.cy
	return dx * dx + dy * dy < self.r * self.r
end

function Circle:vertices()
	local pts = {}
	for i = 1, self.n do
		local a = 2 * math.pi * (i - 1) / self.n
		pts[i] = { self.cx + self.r * math.cos(a), self.cy + self.r * math.sin(a) }
	end
	return pts
end

function Circle:discretise_onto(g, marker, opts)
	marker = marker or 0
	local segs = (opts and opts.n) or self.n
	local first, prev
	for i = 1, segs do
		local a = 2 * math.pi * (i - 1) / segs
		local idx = g:node_add(self.cx + self.r * math.cos(a),
			self.cy + self.r * math.sin(a), marker)
		if i == 1 then first = idx end
		if prev then g:edge_add(prev, idx, marker) end
		prev = idx
	end
	g:edge_add(prev, first, marker)
end

--
-- Rectangle
--

local Rect = setmetatable({}, { __index = Shape })
Rect.__index = Rect

function M.rect(x0, y0, x1, y1)
	if x0 > x1 then x0, x1 = x1, x0 end
	if y0 > y1 then y0, y1 = y1, y0 end
	return setmetatable({ x0 = x0, y0 = y0, x1 = x1, y1 = y1 }, Rect)
end

function Rect:bbox()
	return {
		min_x = self.x0,
		min_y = self.y0,
		max_x = self.x1,
		max_y = self.y1
	}
end

function Rect:centroid()
	return (self.x0 + self.x1) * 0.5, (self.y0 + self.y1) * 0.5
end

function Rect:contains(x, y)
	return x > self.x0 and x < self.x1
		and y > self.y0 and y < self.y1
end

function Rect:vertices()
	return { { self.x0, self.y0 }, { self.x1, self.y0 },
		{ self.x1, self.y1 }, { self.x0, self.y1 } }
end

function Rect:discretise_onto(g, marker, _)
	marker = marker or 0
	local a = g:node_add(self.x0, self.y0, marker)
	local b = g:node_add(self.x1, self.y0, marker)
	local c = g:node_add(self.x1, self.y1, marker)
	local d = g:node_add(self.x0, self.y1, marker)
	g:edge_add(a, b, marker); g:edge_add(b, c, marker)
	g:edge_add(c, d, marker); g:edge_add(d, a, marker)
end

--
-- Arbitrary polygon
--

local Polygon = setmetatable({}, { __index = Shape })
Polygon.__index = Polygon

function M.polygon(pts)
	assert(#pts >= 3, "polygon requires at least 3 points")
	return setmetatable({ pts = pts }, Polygon)
end

function Polygon:bbox()
	local min_x, min_y = math.huge, math.huge
	local max_x, max_y = -math.huge, -math.huge
	for _, p in ipairs(self.pts) do
		if p[1] < min_x then min_x = p[1] end
		if p[1] > max_x then max_x = p[1] end
		if p[2] < min_y then min_y = p[2] end
		if p[2] > max_y then max_y = p[2] end
	end
	return { min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y }
end

function Polygon:centroid()
	return centroid(self.pts)
end

function Polygon:contains(x, y)
	return point_in_polygon(self.pts, x, y)
end

function Polygon:vertices()
	return self.pts
end

function Polygon:discretise_onto(g, marker, _)
	marker = marker or 0
	local first, prev
	for i, p in ipairs(self.pts) do
		local idx = g:node_add(p[1], p[2], marker)
		if i == 1 then first = idx end
		if prev then g:edge_add(prev, idx, marker) end
		prev = idx
	end
	g:edge_add(prev, first, marker)
end

return M
