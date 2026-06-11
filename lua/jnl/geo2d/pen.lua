-- geo2d/pen.lua  -  fluent pen / turtle API for building Curve2D shapes
-- <jed@nelson.ac> // 2026-06-10

local C = require("jnl.geo2d.curve")

local TAU = 2.0 * math.pi
local DEG = math.pi / 180.0

--
-- Internal helpers
--

local function norm(b) return b % 360.0 end

local function bear_dir(bearing_deg)
	local r = bearing_deg * DEG
	return math.sin(r), math.cos(r)
end

local function dir_bear(dx, dy)
	return norm(math.atan(dx, dy) / DEG)
end

local function fillet_params(px, py, heading_deg, delta_deg, radius)
	local br     = heading_deg * DEG
	local cos_b  = math.cos(br)
	local sin_b  = math.sin(br)
	local sign   = (delta_deg >= 0) and 1.0 or -1.0
	local cx     = px + radius * (sign * cos_b)
	local cy     = py + radius * (-sign * sin_b)
	local theta0 = math.atan(py - cy, px - cx)
	local theta1 = theta0 - delta_deg * DEG
	local qx     = cx + radius * math.cos(theta1)
	local qy     = cy + radius * math.sin(theta1)
	return cx, cy, theta0, theta1, qx, qy
end

--
-- Pen object
--

---@class PenHint
---@field n    integer?  Sample count override for this segment's PSLG lowering.
---@field dist Dist1D?   Distribution override for this segment's PSLG lowering.

---@class PenSegment
---@field curve Curve2D
---@field tag   string?
---@field hint  PenHint?

---@class Pen
---@field private sx      number?
---@field private sy      number?
---@field private x       number?
---@field private y       number?
---@field private heading number
---@field private closed  boolean
---@field segs    PenSegment[]
---@field tags table<string, Curve2D>  Named segments, keyed by tag.
local Pen = {}
Pen.__index = Pen

---@return Pen
local function new_pen()
	return setmetatable({
		sx      = nil,
		sy      = nil,
		x       = nil,
		y       = nil,
		heading = 0.0,
		segs    = {},
		tags    = {},
		closed  = false,
	}, Pen)
end

local function push(pen, curve)
	pen.segs[#pen.segs + 1] = { curve = curve, tag = nil, hint = nil }
	return pen
end

local function need_start(pen)
	assert(pen.x, "pen: call :at(x, y) before any movement")
end

local function need_open(pen)
	assert(not pen.closed, "pen: shape is already closed")
end

--
-- Initialisation
--

---Set the starting position and optionally the initial heading.
---@param x               number
---@param y               number
---@param initial_bearing number?  Bearing in degrees; default 0 (north).
---@return Pen
function Pen:at(x, y, initial_bearing)
	assert(self.sx == nil, "pen: :at() has already been called")

	self.sx = x
	self.sy = y
	self.x = x
	self.y = y
	self.heading = norm(initial_bearing or 0.0)
	return self
end

--
-- Straight movement
--

---Move at an absolute bearing (0 = north, clockwise) for the given distance.
---@param bearing_deg number
---@param dist        number  Must be positive.
---@return Pen
function Pen:bear(bearing_deg, dist)
	need_start(self)
	need_open(self)
	assert(dist > 0, "pen: dist must be positive")

	bearing_deg = norm(bearing_deg)
	local dx, dy = bear_dir(bearing_deg)
	local x1 = self.x + dx * dist
	local y1 = self.y + dy * dist
	push(self, C.line(self.x, self.y, x1, y1))

	self.x = x1
	self.y = y1
	self.heading = bearing_deg
	return self
end

---Turn relative to the current heading, then move forward.
---@param delta_deg number
---@param dist      number
---@return Pen
function Pen:turn(delta_deg, dist)
	need_start(self)
	return self:bear(self.heading + delta_deg, dist)
end

---@param d number
---@return Pen
function Pen:north(d) return self:bear(0, d) end

---@param d number
---@return Pen
function Pen:east(d) return self:bear(90, d) end

---@param d number
---@return Pen
function Pen:south(d) return self:bear(180, d) end

---@param d number
---@return Pen
function Pen:west(d) return self:bear(270, d) end

---Straight line to an absolute position.
---@param x number
---@param y number
---@return Pen
function Pen:line_to(x, y)
	need_start(self)
	need_open(self)

	local dx = x - self.x
	local dy = y - self.y
	local dist = math.sqrt(dx * dx + dy * dy)
	assert(dist > 1e-14,
		"pen: line_to degenerate — target coincides with current position")

	push(self, C.line(self.x, self.y, x, y))

	self.x = x
	self.y = y
	self.heading = dir_bear(dx, dy)
	return self
end

--
-- Arc movement
--

---Turn by delta_deg through a circular arc of the given radius, then
---optionally continue straight for dist.
---@param delta_deg number  Signed turn angle in degrees.
---@param radius    number
---@param dist      number?  Optional straight segment after the arc.
---@return Pen
function Pen:arc_turn(delta_deg, radius, dist)
	need_start(self)
	need_open(self)
	assert(math.abs(delta_deg) > 1e-10,
		"pen: arc_turn delta_deg must be non-zero")
	assert(radius > 0, "pen: arc radius must be positive")

	local cx, cy, theta0, theta1, qx, qy =
		fillet_params(self.x, self.y, self.heading, delta_deg, radius)
	push(self, C.arc(cx, cy, radius, theta0, theta1))

	self.x = qx
	self.y = qy
	self.heading = norm(self.heading + delta_deg)
	if dist and dist > 0 then return self:bear(self.heading, dist) end
	return self
end

---Arc to an absolute target point.
---@param x         number
---@param y         number
---@param radius    number
---@param clockwise boolean?
---@return Pen
function Pen:arc_to(x, y, radius, clockwise)
	need_start(self); need_open(self)
	local px, py = self.x, self.y
	local dx = x - px
	local dy = y - py
	local chord = math.sqrt(dx * dx + dy * dy)
	assert(chord > 1e-14,
		"pen: arc_to degenerate — target coincides with current position")
	assert(2.0 * radius >= chord - 1e-12,
		("pen: arc_to radius %.6g is too small for chord %.6g")
		:format(radius, chord))

	local h = math.sqrt(math.max(0.0, radius * radius - (chord * 0.5) ^ 2))
	local nx = -dy / chord
	local ny = dx / chord
	local sign = clockwise and -1.0 or 1.0
	local cx = (px + x) * 0.5 + sign * h * nx
	local cy = (py + y) * 0.5 + sign * h * ny
	local theta0 = math.atan(py - cy, px - cx)
	local theta1 = math.atan(y - cy, x - cx)

	if not clockwise and theta1 < theta0 then
		theta1 = theta1 + TAU
	elseif clockwise and theta1 > theta0 then
		theta1 = theta1 - TAU
	end

	push(self, C.arc(cx, cy, radius, theta0, theta1))

	self.x = x
	self.y = y
	local tdx, tdy
	if clockwise then
		tdx = math.sin(theta1); tdy = -math.cos(theta1)
	else
		tdx = -math.sin(theta1); tdy = math.cos(theta1)
	end

	self.heading = dir_bear(tdx, tdy)
	return self
end

--
-- Close
--

---Draw a straight line back to the starting point.
---@return Pen
function Pen:close()
	need_start(self)
	assert(not self.closed, "pen: already closed")
	local dx = self.sx - self.x
	local dy = self.sy - self.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > 1e-12 then
		push(self, C.line(self.x, self.y, self.sx, self.sy))
		self.heading = dir_bear(dx, dy)
	end

	self.x = self.sx
	self.y = self.sy
	self.closed = true
	return self
end

--
-- Annotation / metadata
--

---Tag the most recently drawn segment with a name.
---
---Tags are unique: re-using a name raises an error.  Use `:get(name)` to
---retrieve the curve later.
---@param name string
---@return Pen
function Pen:tag(name)
	assert(#self.segs > 0, "pen: no segment to tag")
	assert(not self.tags[name],
		("pen: tag %q is already in use"):format(name))

	local seg = self.segs[#self.segs]
	seg.tag = name
	self.tags[name] = seg.curve
	return self
end

---Attach discretisation hints to the most recently drawn segment.
---
---Hints are consumed during PSLG lowering.  Calling `:hint()` on an
---untagged segment is allowed; the hint is stored but will only have
---effect if the segment is later tagged before `:build()` is called —
---in practice, always call `:tag()` before `:hint()`.
---
---```lua
---pen:at(0,0)
---    :line_to(0, H)   :tag("inlet")   :hint({ n = 32 })
---    :line_to(L, H)   :tag("top")
---    :line_to(L, 0)   :tag("outlet")  :hint({ n = 32, dist = curve.cosine_both() })
---    :close()
---```
---@param opts PenHint
---@return Pen
function Pen:hint(opts)
	assert(#self.segs > 0, "pen: no segment to hint")
	self.segs[#self.segs].hint = opts
	return self
end

--
-- Build / access
--

---Build and return the complete Curve2D from all segments.
---@return Curve2D
function Pen:build()
	local n = #self.segs
	assert(n > 0, "pen: no segments to build")

	if n == 1 then
		return self.segs[1].curve:clone()
	end

	local curves = {}
	for i, seg in ipairs(self.segs) do
		curves[i] = seg.curve
	end

	return C.chain(curves)
end

---Return a previously tagged segment as a Curve2D.
---@param name string
---@return Curve2D
function Pen:get(name)
	local c = self.tags[name]
	assert(c, ("pen: no segment tagged %q"):format(name))
	return c
end

---Return the current pen position.
---@return number x
---@return number y
function Pen:pos()
	assert(self.x, "pen: :at() has not been called yet")
	return self.x, self.y
end

return new_pen
