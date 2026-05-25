-- mesh2d/tri.lua
-- <jed@nelson.ac> // 2026-05-25

local mesh2d = require("jnl.mesh2d_internal")
local M = {}

M._doc = "Fluent triangulation spec builder for PSLG meshing"

M._doc_subsection = {
	"Create triangulation specs with tri.spec(), then usually call from_registry(registry) for domains built with geo2d.domain.",
	"Choose one sizing strategy such as resolution(pslg, h), cell_count(pslg, n), or max_area(area).",
	"Use min_angle, conforming, quiet, and region_areas to tune Triangle.c options before calling triangulate(pslg).",
	"triangulate returns mesh, 'ok' on success, or nil plus an error message on failure.",
}

M._api = {
	spec = {
		args = "",
		ret = "Spec",
		doc = "Create a new triangulation spec"
	},
}

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

--
-- Type annotation
--

M._types = {
	Spec = {
		doc         = "Fluent builder wrapping TriSpec + TriOpts; all methods return self for chaining",
		constructor = "tri.spec()",
		methods     = {
			from_registry = {
				args = "registry:table",
				ret = "Spec",
				doc = "Populate patches/baffles/regions from a domain registry { patches, baffles, regions }"
			},
			min_angle     = {
				args = "deg:number",
				ret = "Spec",
				doc = "Set minimum triangle angle in degrees"
			},
			max_area      = {
				args = "area:number",
				ret = "Spec",
				doc = "Set global maximum triangle area"
			},
			region_areas  = {
				args = "enabled:bool?",
				ret = "Spec",
				doc = "Enable per-region area constraints (default true)"
			},
			conforming    = {
				args = "enabled:bool?",
				ret = "Spec",
				doc = "Enable conforming Delaunay triangulation (default true)"
			},
			quiet         = {
				args = "enabled:bool?",
				ret = "Spec",
				doc = "Suppress Triangle.c stdout output (default true)"
			},
			cell_count    = {
				args = "pslg:PSLG, n:int",
				ret = "Spec",
				doc = "Target cell count; derives global max_area from PSLG bounding area"
			},
			resolution    = {
				args = "pslg:PSLG, res:number",
				ret = "Spec",
				doc = "Target mean cell edge length; derives global max_area"
			},
			patch         = {
				args = "name:string, marker:int",
				ret = "Spec",
				doc = "Register a named boundary patch marker"
			},
			baffle        = {
				args = "name:string, marker:int",
				ret = "Spec",
				doc = "Register a named baffle marker"
			},
			region        = {
				args = "name:string, marker:int",
				ret = "Spec",
				doc = "Register a named region marker"
			},
			triangulate   = {
				args = "pslg:PSLG",
				ret = "Mesh, string",
				doc = "Run triangulation. Returns mesh+'ok' on success, nil+errmsg on failure."
			},
		},
	},
}

return M
