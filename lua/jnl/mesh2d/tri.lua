-- mesh2d/tri.lua
-- <jed@nelson.ac> // 2026-05-25

local mesh2d = require("jnl.mesh2d_internal")
local M = {}

local Spec = {}
Spec.__index = Spec

function M.spec()
	local s = setmetatable({
		_spec = mesh2d.spec_new(),
		_opts = mesh2d.opts_default(),
		_pslg = nil, -- set lazily in cell_count/resolution
	}, Spec)
	return s
end

function Spec:from_registry(registry)
	for name, marker in pairs(registry.patches or {}) do
		self._spec:add_patch(marker, name)
	end
	for name, marker in pairs(registry.baffles or {}) do
		self._spec:add_baffle(marker, name)
	end
	for name, marker in pairs(registry.regions or {}) do
		self._spec:add_region(marker, name)
	end
	return self
end

function Spec:min_angle(deg)
	self._opts = self._opts:set_min_angle(deg)
	return self
end

function Spec:max_area(area)
	self._opts = self._opts:set_global_max_area(area)
	return self
end

function Spec:region_areas(enabled)
	self._opts = self._opts:enable_region_areas(enabled ~= false)
	return self
end

function Spec:conforming(enabled)
	self._opts = self._opts:set_conforming_delaunay(enabled ~= false)
	return self
end

function Spec:quiet(enabled)
	self._opts = self._opts:set_quiet(enabled ~= false)
	return self
end

function Spec:cell_count(pslg, n)
	self._opts = self._opts:set_cell_count(pslg, n)
	return self
end

function Spec:resolution(pslg, res)
	self._opts = self._opts:set_resolution(pslg, res)
	return self
end

function Spec:patch(name, marker)
	self._spec:add_patch(marker, name)
	return self
end

function Spec:baffle(name, marker)
	self._spec:add_baffle(marker, name)
	return self
end

function Spec:region(name, marker)
	self._spec:add_region(marker, name)
	return self
end

function Spec:triangulate(pslg)
	self._spec:set_opts(self._opts)
	return mesh2d.triangulate(pslg, self._spec)
end

return M
