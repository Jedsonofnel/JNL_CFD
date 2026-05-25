-- showcase/pslg_gallery.lua
-- <jed@nelson.ac> // 2026-05-25

local shapes = require("jnl.geo2d.shapes")
local domain = require("jnl.geo2d.domain")
local tri    = require("jnl.mesh2d.tri")
local ui     = require("jnl.ui")
local repl   = require("jnl.repl").new()

--
-- PSLGs
--

local function channel()
	local dom = domain.new(shapes.rect(0, 0, 4, 1), { default = "wall" })
		:name_boundary("inlet", shapes.line(0, 0, 0, 1))
		:name_boundary("outlet", shapes.line(4, 0, 4, 1))
		:add_region_seed("fluid", 2, 0.5, { max_area = 0.02 })
	return dom:build()
end

local function lshape()
	local outer = shapes.polygon({
		{ 300, 100 }, { 500, 100 }, { 500, 400 },
		{ 100, 400 }, { 100, 250 }, { 300, 250 },
	})
	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(100, 400, 100, 250))
		:name_boundary("outlet", shapes.line(500, 100, 500, 400))
		:add_line("divider", { { 300, 250 }, { 500, 250 } })
		:add_hole(shapes.circle(300, 330, 40, 16), "hole_wall")
		:add_region_seed("upper", 250, 330, { max_area = 800 })
		:add_region_seed("lower", 400, 175, { max_area = 200 })
	return dom:build()
end

local function annulus(r_inner)
	r_inner = r_inner or 0.3
	assert(r_inner > 0 and r_inner < 1.0, "r_inner must be in (0, 1)")
	local dom = domain.new(shapes.circle(0, 0, 1.0, 48), { default = "outer_wall" })
		:add_hole(shapes.circle(0, 0, r_inner, 32), "inner_wall")
		:add_region_seed("fluid", (1.0 - r_inner) * 0.5, 0, { max_area = 0.01 })
	return dom:build()
end

local function cylinder_array(n)
	n = n or 3
	assert(n >= 1 and n <= 8, "n must be in [1, 8]")
	local dom = domain.new(shapes.rect(0, 0, n + 1, 1), { default = "wall" })
		:name_boundary("inlet", shapes.line(0, 0, 0, 1))
		:name_boundary("outlet", shapes.line(n + 1, 0, n + 1, 1))
	local r = 0.15
	for i = 1, n do
		dom:add_hole(shapes.circle(i * 1.0, 0.5, r, 24), "cylinder")
	end
	dom:add_region_seed("fluid", 0.5, 0.5, { max_area = 0.01 })
	return dom:build()
end

--
-- Mesh + display helpers
--

local function triangulate(pslg, registry)
	local mesh, err = tri.spec()
		:from_registry(registry)
		:min_angle(25)
		:region_areas(true)
		:quiet(true)
		:triangulate(pslg)
	assert(mesh, err)
	return mesh
end

local function show_pslg(pslg)
	ui.display_pslg(pslg)
end

local function show_mesh(mesh)
	ui.display_mesh(mesh)
end

--
-- Register
--

repl:register("channel", channel, "() -> pslg, registry   Rectangular channel; inlet/outlet/wall")
repl:register("lshape", lshape, "() -> pslg, registry   L-shaped domain; dividing line + circular hole")
repl:register("annulus", annulus, "(r_inner?) -> pslg, registry   Annular domain; r_inner default 0.3, outer 1.0")
repl:register("cylinder_array", cylinder_array, "(n?) -> pslg, registry   Channel with n inline cylinders (default 3)")
repl:register("triangulate", triangulate, "(pslg, registry) -> Mesh   Mesh with 25deg min angle, region areas enabled")
repl:register("show_pslg", show_pslg, "(pslg)   Display a PSLG in the viewer")
repl:register("show_mesh", show_mesh, "(mesh)   Display a mesh in the viewer")


print("PSLG gallery — type ,help to list available functions.")
repl:run()
