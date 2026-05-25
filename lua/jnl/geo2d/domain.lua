-- geo2d/domain.lua
-- <jed@nelson.ac> // 2026-05-25

local geo2d = require("jnl.geo2d_internal")
local M = {}

M._doc = [[
Composite 2D domain builder. Assembles a PSLG from named boundary shapes,
internal lines, holes, and region seeds. Produces a registry of name→marker
mappings consumed by mesh2d.tri.
]]

M._api = {
	new             = {
		args = "outer:Shape, opts:table?",
		ret = "Domain",
		doc = "Create domain with given outer boundary. opts: { default='wall' }"
	},
	name_boundary   = {
		args = "self, name:string, shape:Line, kind:string?",
		ret = "Domain",
		doc = "Register a named boundary segment lying on the outer or hole boundary. kind: 'patch'|'baffle'"
	},
	add_hole        = {
		args = "self, shape:Shape, name:string?",
		ret = "Domain",
		doc = "Add a closed inner hole. name registers its boundary edges as a patch."
	},
	add_line        = {
		args = "self, name:string, pts:number[][]|Line, kind:string?",
		ret = "Domain",
		doc = "Add an internal line. kind: 'patch'|'baffle' (default 'patch')"
	},
	add_region_seed = {
		args = "self, name:string, x:number, y:number, opts:table?",
		ret = "Domain",
		doc = "Place a region seed. opts: { max_area=-1, marker=auto }"
	},
	check           = {
		args = "self",
		ret = "true|nil, err:string",
		doc = "Validate all named boundaries lie on domain geometry."
	},
	build           = {
		args = "self",
		ret = "pslg:PSLG, registry:table",
		doc = "Discretise all geometry. Returns pslg + name→marker registry."
	},
}

--
-- Geometry helpers
--

local EPS = 1e-9

local function pt_eq(ax, ay, bx, by, eps)
	eps = eps or EPS
	return math.abs(ax - bx) < eps and math.abs(ay - by) < eps
end

local function pt_on_segment(px, py, ax, ay, bx, by, eps)
	eps = eps or EPS
	local cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
	-- Scale tolerance by segment length so it's not absolute
	if math.abs(cross) > eps * (math.abs(bx - ax) + math.abs(by - ay) + 1) then
		return false
	end
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	if len2 < eps * eps then return pt_eq(px, py, ax, ay, eps) end
	local t = ((px - ax) * dx + (py - ay) * dy) / len2
	return t >= -eps and t <= 1 + eps
end

-- Does every segment of line_pts lie on some edge of boundary_pts?
local function polyline_on_boundary(line_pts, boundary_pts, closed)
	local n = #boundary_pts
	local limit = closed and n or n - 1
	for i = 1, #line_pts - 1 do
		local p1, p2 = line_pts[i], line_pts[i + 1]
		local found = false
		for j = 1, limit do
			local a = boundary_pts[j]
			local b = boundary_pts[(j % n) + 1]
			if pt_on_segment(p1[1], p1[2], a[1], a[2], b[1], b[2])
				and pt_on_segment(p2[1], p2[2], a[1], a[2], b[1], b[2]) then
				found = true
				break
			end
		end
		if not found then return false end
	end
	return true
end

-- Given an edge midpoint, find the marker from a list of named boundary entries.
-- Returns marker or nil.
local function match_boundary_marker(mx, my, boundaries)
	for _, b in ipairs(boundaries) do
		local bv = b.shape:vertices()
		for i = 1, #bv - 1 do
			if pt_on_segment(mx, my, bv[i][1], bv[i][2], bv[i + 1][1], bv[i + 1][2]) then
				return b.marker
			end
		end
	end
	return nil
end

--
-- Marker registry
--

local function get_or_alloc_marker(self, name)
	if self._name_to_marker[name] then
		return self._name_to_marker[name]
	end
	local m = self._next_marker
	self._next_marker = m + 1
	self._name_to_marker[name] = m
	return m
end

--
-- Domain
--

local Domain = {}
Domain.__index = Domain

function M.new(outer, opts)
	assert(outer, "domain requires an outer boundary shape")
	opts = opts or {}
	return setmetatable({
		outer           = outer,
		_default        = opts.default or nil,
		_boundaries     = {},
		_holes          = {},
		_lines          = {},
		_seeds          = {},
		_next_marker    = 1,
		_name_to_marker = {},
	}, Domain)
end

function Domain:name_boundary(name, shape, kind)
	assert(type(name) == "string", "boundary name must be a string")
	local marker = get_or_alloc_marker(self, name) -- fix: pass name
	table.insert(self._boundaries, {
		name = name,
		shape = shape,
		kind = kind or "patch",
		marker = marker,
	})
	return self
end

function Domain:add_hole(shape, name)
	local marker = name and get_or_alloc_marker(self, name) or 0
	table.insert(self._holes, { shape = shape, name = name, marker = marker })
	return self
end

function Domain:add_line(name, pts, kind)
	assert(type(name) == "string", "line name must be a string")
	-- Accept a shapes.Line object or a raw pts table
	if type(pts) == "table" and pts.vertices then
		pts = pts:vertices()
	end
	assert(type(pts) == "table" and #pts >= 2, "line needs at least 2 points")
	local marker = get_or_alloc_marker(self, name)
	table.insert(self._lines, {
		name = name,
		pts = pts,
		kind = kind or "patch",
		marker = marker,
	})
	return self
end

function Domain:add_region_seed(name, x, y, opts)
	opts = opts or {}
	local marker = opts.marker or get_or_alloc_marker(self, name)
	table.insert(self._seeds, {
		name = name,
		x = x,
		y = y,
		max_area = opts.max_area or -1.0,
		marker = marker,
	})
	return self
end

--
-- Validation
--

function Domain:check()
	local outer_verts = self.outer:vertices()
	for _, b in ipairs(self._boundaries) do
		local line_verts = b.shape:vertices()
		local ok = polyline_on_boundary(line_verts, outer_verts, true)
		if not ok then
			for _, h in ipairs(self._holes) do
				if polyline_on_boundary(line_verts, h.shape:vertices(), true) then
					ok = true
					break
				end
			end
		end
		if not ok then
			return nil, string.format(
				"boundary '%s': does not lie on any domain boundary", b.name)
		end
	end
	return true
end

--
-- Build helpers (module-local, explicit args — no closure capture)
--

local function discretise_outer(self, g)
	local verts = self.outer:vertices()
	local n = #verts
	local nodes = {}
	for i, v in ipairs(verts) do
		nodes[i] = g:node_find_or_add(v[1], v[2], 0)
	end
	for i = 1, n do
		local j = (i % n) + 1
		local ax, ay = verts[i][1], verts[i][2]
		local bx, by = verts[j][1], verts[j][2]
		local mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
		local marker = match_boundary_marker(mx, my, self._boundaries)
			or (self._default and get_or_alloc_marker(self, self._default))
			or 0
		g:edge_add(nodes[i], nodes[j], marker)
	end
end

local function discretise_hole(h, g, boundaries)
	local verts = h.shape:vertices()
	local n = #verts
	local nodes = {}
	for i, v in ipairs(verts) do
		nodes[i] = g:node_find_or_add(v[1], v[2], 0)
	end
	-- Collect only the boundaries whose name matches this hole's name,
	-- so per-segment overrides on the hole boundary work the same way
	-- as on the outer boundary.
	local hole_boundaries = {}
	if h.name then
		for _, b in ipairs(boundaries) do
			if b.name == h.name then
				table.insert(hole_boundaries, b)
			end
		end
	end
	for i = 1, n do
		local j = (i % n) + 1
		local ax, ay = verts[i][1], verts[i][2]
		local bx, by = verts[j][1], verts[j][2]
		local mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
		local marker = match_boundary_marker(mx, my, hole_boundaries)
			or h.marker
			or 0
		g:edge_add(nodes[i], nodes[j], marker)
	end
	local cx, cy = h.shape:centroid()
	g:hole_add(cx, cy)
end

local function discretise_lines(lines, g)
	for _, line in ipairs(lines) do
		local prev
		for _, pt in ipairs(line.pts) do
			local idx = g:node_find_or_add(pt[1], pt[2], 0)
			if prev then g:edge_add(prev, idx, line.marker) end
			prev = idx
		end
	end
end

local function place_seeds(seeds, g)
	for _, s in ipairs(seeds) do
		g:region_add(s.x, s.y, s.marker, s.max_area)
	end
end

local function build_registry(self)
	local registry = { patches = {}, baffles = {}, regions = {} }

	local function reg_named(name, marker, kind)
		local bucket = (kind == "baffle") and registry.baffles or registry.patches
		bucket[name] = marker
	end

	for _, b in ipairs(self._boundaries) do
		reg_named(b.name, b.marker, b.kind)
	end
	for _, l in ipairs(self._lines) do
		reg_named(l.name, l.marker, l.kind)
	end
	for _, h in ipairs(self._holes) do
		if h.name then reg_named(h.name, h.marker, "patch") end
	end
	for _, s in ipairs(self._seeds) do
		registry.regions[s.name] = s.marker
	end
	if self._default and self._name_to_marker[self._default] then
		registry.patches[self._default] = self._name_to_marker[self._default]
	end

	return registry
end

--
-- Build
--

function Domain:build()
	local ok, err = self:check()
	if not ok then error("domain:build() validation failed: " .. err) end

	local g = geo2d.pslg_new()
	discretise_outer(self, g)
	for _, h in ipairs(self._holes) do
		discretise_hole(h, g, self._boundaries)
	end
	discretise_lines(self._lines, g)
	place_seeds(self._seeds, g)

	return g, build_registry(self)
end

return M
