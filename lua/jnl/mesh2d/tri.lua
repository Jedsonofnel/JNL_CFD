-- lua/jnl/mesh2d/tri.lua - unstructured triangulation via Triangle.c
-- <jed@nelson.ac> // 2026-06-12

--- Fluent specification builder and entry points for Triangle-backed
--- unstructured mesh generation.
---
--- Typical workflow:
---
---     local pslg = curve.discretise(domain_curve, marker)
---     local mesh = tri.spec()
---         :from_domain_reg(reg)
---         :min_angle(28)
---         :resolution(pslg, 0.05)
---         :triangulate(pslg)
---
--- For Domain2D input use tri.from_domain()
local M = {}

local opt = require("jnl.core.optional")
local I = opt.require("jnl.trimesh2d_internal")

--
-- Spec builder
--

---@class TriSpecBuilder
---@field opts table
---@field spec table
local Spec = {}
Spec.__index = Spec

--- Create a triangulation specification.
---@return TriSpecBuilder
function M.spec()
	return setmetatable({
		spec = I.spec_new(),
		opts = I.opts_default(),
	}, Spec)
end

--- Populate patch, baffle, and region tags from a MarkerRegistry.
---
--- The registry is produced by domain.from_pen() and carries the name→marker
--- mapping built during pen tracing.
---@param registry MarkerRegistry
---@return TriSpecBuilder self
function Spec:from_domain_reg(registry)
	for name, marker in pairs(registry.map or {}) do
		self.spec:add_patch(marker, name)
	end
	return self
end

---@param deg number Minimum interior angle in degrees.
---@return TriSpecBuilder self
function Spec:min_angle(deg)
	self.opts = self.opts:set_min_angle(deg)
	return self
end

---@param area number Global maximum triangle area.
---@return TriSpecBuilder self
function Spec:max_area(area)
	self.opts = self.opts:set_global_max_area(area)
	return self
end

--- Derive the global max area from a target cell count.
---@param pslg PSLG
---@param n    integer
---@return TriSpecBuilder self
function Spec:cell_count(pslg, n)
	self.opts = self.opts:set_cell_count(pslg, n)
	return self
end

--- Derive the global max area from a target mean edge length.
---@param pslg PSLG
---@param res  number
---@return TriSpecBuilder self
function Spec:resolution(pslg, res)
	self.opts = self.opts:set_resolution(pslg, res)
	return self
end

---@param enabled boolean?  Defaults to true.
---@return TriSpecBuilder self
function Spec:region_areas(enabled)
	self.opts = self.opts:enable_region_areas(enabled ~= false)
	return self
end

---@param enabled boolean?
---@return TriSpecBuilder self
function Spec:conforming(enabled)
	self.opts = self.opts:set_conforming_delaunay(enabled ~= false)
	return self
end

---@param enabled boolean?
---@return TriSpecBuilder self
function Spec:quiet(enabled)
	self.opts = self.opts:set_quiet(enabled ~= false)
	return self
end

--- Add a named patch tag directly.
---@param name   string
---@param marker integer
---@return TriSpecBuilder self
function Spec:patch(name, marker)
	self.spec:add_patch(marker, name)
	return self
end

---@param name   string
---@param marker integer
---@return TriSpecBuilder self
function Spec:baffle(name, marker)
	self.spec:add_baffle(marker, name)
	return self
end

---@param name   string
---@param marker integer
---@return TriSpecBuilder self
function Spec:region(name, marker)
	self.spec:add_region(marker, name)
	return self
end

--- Triangulate a PSLG and return a Mesh2D.
---@param pslg PSLG
---@return Mesh2D? mesh
---@return string?  err
function Spec:triangulate(pslg)
	self.spec:set_opts(self.opts)
	return I.triangulate(pslg, self.spec)
end

--
-- Domain2D lowering
--

--- Lower a Domain2D to a PSLG suitable for triangulation.
---
--- Samples each boundary curve at n points, adds nodes and constrained
--- edges to a new PSLG, and inserts hole and region seeds.
---@param domain Domain2D
---@param opts?  { n:integer? }
---@return PSLG?  pslg
---@return string? err
function M.pslg_from_domain(domain, opts) -- luacheck: ignore domain opts
	return nil, "pslg_from_domain: not yet implemented"
end

--- Triangulate a Domain2D directly.
---@param domain Domain2D
---@param spec   TriSpecBuilder
---@param opts?  { n:integer? }
---@return Mesh2D? mesh
---@return string?  err
function M.from_domain(domain, spec, opts)
	local pslg, err = M.pslg_from_domain(domain, opts)
	if not pslg then return nil, err end
	return spec:triangulate(pslg)
end

return M
