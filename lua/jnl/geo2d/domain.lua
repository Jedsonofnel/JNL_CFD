-- geo2d/domain.lua - 2D domain library for concentric shapes
-- <jed@nelson.ac> // 2026-05-21

-- local shapes = require("jnl.geo2d.shapes")
local geo2d = require("jnl.geo2d_internal")

local M = {}

--
-- Domain
--

local Domain = {}
Domain.__index = Domain

function Domain.new(outer)
	assert(outer, "domain requires an outer boundary shape")
	local self = {
		outer = outer,
		inners = {},
	}
	return setmetatable(self, Domain)
end

M.new = Domain.new

function Domain:add_hole(shape, marker)
	marker = marker or (#self.inners + 2)
	local ok, err = self:_check_shape(shape)
	if not ok then return nil, err end
	table.insert(self.inners, { shape = shape, marker = marker, is_hole = true })
	return self
end

function Domain:add_region(shape, marker)
	marker = marker or (#self.inners + 2)
	local ok, err = self:_check_shape(shape)
	if not ok then return nil, err end
	table.insert(self.inners, { shape = shape, marker = marker, is_hole = false })
	return self
end

function Domain:_check_shape(shape)
	-- must be fully inside outer
	local cx, cy = shape:centroid()
	if not self.outer:contains(cx, cy) then
		return nil, "shape centroid is not inside outer boundary"
	end
	-- must not intersect outer
	if self.outer:intersects(shape) then
		return nil, "shape intersects outer boundary"
	end
	-- must not intersect any existing inner shape
	for _, entry in ipairs(self.inners) do
		if entry.shape:intersects(shape) then
			return nil, "shape intersects an existing inner shape"
		end
		-- must not contain each other
		local ex, ey = entry.shape:centroid()
		if shape:contains(ex, ey) or entry.shape:contains(cx, cy) then
			return nil, "shapes may not contain one another"
		end
	end
	return true
end

function Domain:check()
	for i, a in ipairs(self.inners) do
		local ok, err = self:_check_shape(a.shape)
		if not ok then
			return nil, string.format("inner shape %d: %s", i, err)
		end
	end
	return true
end

function Domain:build()
	local g = geo2d.pslg_new()

	-- outer boundary gets marker 1
	self.outer:discretise_onto(g, 1)

	-- inner shapes
	for _, entry in ipairs(self.inners) do
		entry.shape:discretise_onto(g, entry.marker)
		if entry.is_hole then
			local cx, cy = entry.shape:centroid()
			g:hole_add(cx, cy)
		end
	end

	return g
end

return M
