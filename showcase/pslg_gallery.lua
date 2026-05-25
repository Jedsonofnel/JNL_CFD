-- showcase/pslg_gallery.lua - Interactive PSLG gallery for simple CFD geometries
-- <jed@nelson.ac> // 2026-05-25

local repl = require("jnl.repl").new()

local shapes = require("jnl.geo2d.shapes")
local domain = require("jnl.geo2d.domain")
local tri = require("jnl.mesh2d.tri")
local mesh2d = require("jnl.mesh2d")
local ui = require("jnl.ui")

--
-- Helpers
--

local function opt(opts, key, default)
	if opts == nil or opts[key] == nil then
		return default
	end

	return opts[key]
end

local function build_checked(dom)
	local ok, err = dom:check()
	if not ok then
		error(err)
	end

	return dom:build()
end

local function mesh_from(pslg, registry, opts)
	opts = opts or {}

	local spec = tri.spec()
		:from_registry(registry)
		:min_angle(opt(opts, "min_angle", 28))
		:conforming(opt(opts, "conforming", true))
		:quiet(opt(opts, "quiet", true))
		:region_areas(opt(opts, "region_areas", true))

	if opts.max_area then
		spec:max_area(opts.max_area)
	elseif opts.cell_count then
		spec:cell_count(pslg, opts.cell_count)
	else
		spec:resolution(pslg, opt(opts, "resolution", 0.08))
	end

	local mesh, status = spec:triangulate(pslg)
	if not mesh then
		error(status)
	end

	return mesh
end

local function mesh_summary(mesh)
	return {
		n_cells = mesh:n_cells(),
		n_faces = mesh:n_faces(),
		n_internal_faces = mesh:n_internal_faces(),
		n_patches = mesh:n_patches(),
		mean_cell_size = mesh:mean_cell_size(),
		patches = mesh2d.patch_list(mesh),
	}
end

local function print_mesh_summary(mesh)
	repl:pp(mesh_summary(mesh))
	return mesh
end

local function show_pslg(pslg)
	ui.display_pslg(pslg)
	return pslg
end

local function show_mesh(mesh)
	ui.display_mesh(mesh)
	return mesh
end

local function build_and_mesh(builder, geom_opts, mesh_opts)
	local pslg, registry = builder(geom_opts or {})
	local mesh = mesh_from(pslg, registry, mesh_opts or {})

	return {
		pslg = pslg,
		registry = registry,
		mesh = mesh,
		summary = mesh_summary(mesh),
	}
end

--
-- Gallery PSLGs
--

local function channel()
	local length = 8.0
	local height = 2.0

	local outer = shapes.rect(-1.5, -1.0, length - 1.5, 1.0)

	return domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(-1.5, -1.0, -1.5, 1.0))
		:name_boundary("outlet", shapes.line(length - 1.5, -1.0, length - 1.5, 1.0))
		:name_boundary("bottom-wall", shapes.line(-1.5, -1.0, length - 1.5, -1.0))
		:name_boundary("top-wall", shapes.line(-1.5, 1.0, length - 1.5, 1.0))
		:add_region_seed("fluid", 0.0, 0.0)
end

local function cylinder(opts)
	opts = opts or {}

	local length = opt(opts, "length", 8.0)
	local height = opt(opts, "height", 2.0)
	local radius = opt(opts, "radius", 0.25)
	local cx = opt(opts, "cx", 0.0)
	local cy = opt(opts, "cy", 0.0)
	local segments = opt(opts, "segments", 64)

	local outer = shapes.rect(-1.5, -height / 2, length - 1.5, height / 2)
	local body = shapes.circle(cx, cy, radius, segments)

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(-1.5, -height / 2, -1.5, height / 2))
		:name_boundary("outlet", shapes.line(length - 1.5, -height / 2, length - 1.5, height / 2))
		:name_boundary("bottom-wall", shapes.line(-1.5, -height / 2, length - 1.5, -height / 2))
		:name_boundary("top-wall", shapes.line(-1.5, height / 2, length - 1.5, height / 2))
		:add_hole(body, "cylinder")
		:add_region_seed("fluid", cx + radius + 0.5, cy)

	return build_checked(dom)
end

local function square_cylinder(opts)
	opts = opts or {}

	local length = opt(opts, "length", 8.0)
	local height = opt(opts, "height", 2.0)
	local side = opt(opts, "side", 0.45)
	local cx = opt(opts, "cx", 0.0)
	local cy = opt(opts, "cy", 0.0)

	local h = side / 2
	local outer = shapes.rect(-1.5, -height / 2, length - 1.5, height / 2)
	local body = shapes.rect(cx - h, cy - h, cx + h, cy + h)

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(-1.5, -height / 2, -1.5, height / 2))
		:name_boundary("outlet", shapes.line(length - 1.5, -height / 2, length - 1.5, height / 2))
		:name_boundary("bottom-wall", shapes.line(-1.5, -height / 2, length - 1.5, -height / 2))
		:name_boundary("top-wall", shapes.line(-1.5, height / 2, length - 1.5, height / 2))
		:add_hole(body, "square-cylinder")
		:add_region_seed("fluid", cx + side, cy)

	return build_checked(dom)
end

local function triangle_wedge(opts)
	opts = opts or {}

	local length = opt(opts, "length", 8.0)
	local height = opt(opts, "height", 2.0)
	local chord = opt(opts, "chord", 0.8)
	local thickness = opt(opts, "thickness", 0.45)
	local cx = opt(opts, "cx", 0.0)
	local cy = opt(opts, "cy", 0.0)

	local outer = shapes.rect(-1.5, -height / 2, length - 1.5, height / 2)
	local body = shapes.polygon({
		{ cx - chord / 2, cy - thickness / 2 },
		{ cx - chord / 2, cy + thickness / 2 },
		{ cx + chord / 2, cy },
	})

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(-1.5, -height / 2, -1.5, height / 2))
		:name_boundary("outlet", shapes.line(length - 1.5, -height / 2, length - 1.5, height / 2))
		:name_boundary("bottom-wall", shapes.line(-1.5, -height / 2, length - 1.5, -height / 2))
		:name_boundary("top-wall", shapes.line(-1.5, height / 2, length - 1.5, height / 2))
		:add_hole(body, "wedge")
		:add_region_seed("fluid", cx + chord, cy)

	return build_checked(dom)
end

local function backward_facing_step(opts)
	opts = opts or {}

	local inlet_length = opt(opts, "inlet_length", 2.0)
	local outlet_length = opt(opts, "outlet_length", 6.0)
	local inlet_height = opt(opts, "inlet_height", 1.0)
	local outlet_height = opt(opts, "outlet_height", 2.0)
	local step_height = outlet_height - inlet_height

	local x0 = -inlet_length
	local x1 = 0.0
	local x2 = outlet_length
	local y0 = -outlet_height / 2
	local y1 = y0 + step_height
	local y2 = outlet_height / 2

	local outer = shapes.polygon({
		{ x0, y1 },
		{ x0, y2 },
		{ x2, y2 },
		{ x2, y0 },
		{ x1, y0 },
		{ x1, y1 },
	})

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(x0, y1, x0, y2))
		:name_boundary("outlet", shapes.line(x2, y0, x2, y2))
		:name_boundary("top-wall", shapes.line(x0, y2, x2, y2))
		:name_boundary("lower-wall", shapes.line({ { x2, y0 }, { x1, y0 }, { x1, y1 } }))
		:name_boundary("inlet-bottom-wall", shapes.line(x0, y1, x1, y1))
		:add_region_seed("fluid", x1 + 0.5, 0.0)

	return build_checked(dom)
end

local function diffuser(opts)
	opts = opts or {}

	local length = opt(opts, "length", 5.0)
	local inlet_height = opt(opts, "inlet_height", 0.8)
	local outlet_height = opt(opts, "outlet_height", 2.0)

	local x0 = 0.0
	local x1 = length

	local outer = shapes.polygon({
		{ x0, -inlet_height / 2 },
		{ x1, -outlet_height / 2 },
		{ x1, outlet_height / 2 },
		{ x0, inlet_height / 2 },
	})

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(x0, -inlet_height / 2, x0, inlet_height / 2))
		:name_boundary("outlet", shapes.line(x1, -outlet_height / 2, x1, outlet_height / 2))
		:name_boundary("lower-wall", shapes.line(x0, -inlet_height / 2, x1, -outlet_height / 2))
		:name_boundary("upper-wall", shapes.line(x0, inlet_height / 2, x1, outlet_height / 2))
		:add_region_seed("fluid", length / 2, 0.0)

	return build_checked(dom)
end

local function mixing_tee(opts)
	opts = opts or {}

	local length = opt(opts, "length", 6.0)
	local height = opt(opts, "height", 1.0)
	local branch_width = opt(opts, "branch_width", 0.7)
	local branch_height = opt(opts, "branch_height", 2.0)
	local branch_x = opt(opts, "branch_x", 1.5)

	local x0 = -length / 2
	local x1 = length / 2
	local y0 = -height / 2
	local y1 = height / 2
	local bx0 = branch_x - branch_width / 2
	local bx1 = branch_x + branch_width / 2
	local by1 = branch_height

	local outer = shapes.polygon({
		{ x0,  y0 },
		{ x1,  y0 },
		{ x1,  y1 },
		{ bx1, y1 },
		{ bx1, by1 },
		{ bx0, by1 },
		{ bx0, y1 },
		{ x0,  y1 },
	})

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("left-inlet", shapes.line(x0, y0, x0, y1))
		:name_boundary("right-outlet", shapes.line(x1, y0, x1, y1))
		:name_boundary("top-inlet", shapes.line(bx0, by1, bx1, by1))
		:name_boundary("bottom-wall", shapes.line(x0, y0, x1, y0))
		:name_boundary("upper-walls", shapes.line({
			{ x1,  y1 },
			{ bx1, y1 },
			{ bx1, by1 },
		}))
		:name_boundary("inner-walls", shapes.line({
			{ bx0, by1 },
			{ bx0, y1 },
			{ x0,  y1 },
		}))
		:add_region_seed("fluid", 0.0, 0.0)

	return build_checked(dom)
end

local function plate_with_baffle(opts)
	opts = opts or {}

	local length = opt(opts, "length", 6.0)
	local height = opt(opts, "height", 2.0)
	local plate_length = opt(opts, "plate_length", 1.4)
	local plate_x = opt(opts, "plate_x", 0.0)
	local plate_y = opt(opts, "plate_y", 0.0)

	local outer = shapes.rect(-1.5, -height / 2, length - 1.5, height / 2)
	local plate = shapes.line(plate_x - plate_length / 2, plate_y, plate_x + plate_length / 2, plate_y)

	local dom = domain.new(outer, { default = "wall" })
		:name_boundary("inlet", shapes.line(-1.5, -height / 2, -1.5, height / 2))
		:name_boundary("outlet", shapes.line(length - 1.5, -height / 2, length - 1.5, height / 2))
		:name_boundary("bottom-wall", shapes.line(-1.5, -height / 2, length - 1.5, -height / 2))
		:name_boundary("top-wall", shapes.line(-1.5, height / 2, length - 1.5, height / 2))
		:add_line("thin-plate", plate, "baffle")
		:add_region_seed("fluid", 0.0, height / 4)

	return build_checked(dom)
end

--
-- Public REPL functions
--

local galleries = {
	cylinder = cylinder,
	["square-cylinder"] = square_cylinder,
	wedge = triangle_wedge,
	step = backward_facing_step,
	diffuser = diffuser,
	tee = mixing_tee,
	plate = plate_with_baffle,
}

local function pslg(name, opts)
	local builder = galleries[name or "cylinder"]
	if not builder then
		error("unknown PSLG gallery item: " .. tostring(name))
	end

	local g = builder(opts or {})
	repl:register("last-pslg", g, "Most recently built PSLG.")
	return g
end

local function mesh_pslg(name, geom_opts, mesh_opts)
	local builder = galleries[name or "cylinder"]
	if not builder then
		error("unknown PSLG gallery item: " .. tostring(name))
	end

	local result = build_and_mesh(builder, geom_opts or {}, mesh_opts or {})

	repl:register("last-pslg", result.pslg, "Most recently built PSLG.")
	repl:register("last-registry", result.registry, "Registry from the most recently built PSLG.")
	repl:register("last-mesh", result.mesh, "Most recently generated mesh.")
	repl:register("last-summary", result.summary, "Summary for the most recently generated mesh.")

	return print_mesh_summary(result.mesh)
end

local function show_pslg_named(name, opts)
	return show_pslg(pslg(name or "cylinder", opts or {}))
end

local function show_mesh_named(name, geom_opts, mesh_opts)
	return show_mesh(mesh_pslg(name or "cylinder", geom_opts or {}, mesh_opts or {}))
end

local function demo()
	return show_mesh_named("cylinder", {}, { resolution = 0.08 })
end

local function gallery()
	return {
		"cylinder",
		"square-cylinder",
		"wedge",
		"step",
		"diffuser",
		"tee",
		"plate",
	}
end

local function help_gallery()
	print("PSLG gallery examples:")
	print("  (demo)")
	print("  (gallery)")
	print("  (show-pslg :cylinder)")
	print("  (show-pslg :square-cylinder {:side 0.55})")
	print("  (show-pslg :wedge {:chord 1.0 :thickness 0.4})")
	print("  (show-pslg :step {:inlet-height 1.0 :outlet-height 2.2})")
	print("  (show-pslg :diffuser {:inlet-height 0.7 :outlet-height 2.0})")
	print("  (show-pslg :tee {:branch-x 1.0 :branch-height 2.0})")
	print("  (show-pslg :plate {:plate-length 1.5})")
	print("")
	print("Meshing examples:")
	print("  (mesh-pslg :cylinder)")
	print("  (mesh-pslg :cylinder {:radius 0.3} {:resolution 0.05})")
	print("  (mesh-pslg :step {} {:cell-count 2000})")
	print("  (show-mesh :wedge {:chord 1.0} {:resolution 0.06})")
	print("")
	print("Recently generated values:")
	print("  last-pslg")
	print("  last-registry")
	print("  last-mesh")
	print("  last-summary")
end

--
-- REPL registration
--

repl:register("gallery", gallery, "Return the available PSLG gallery item names.")
repl:register("help-gallery", help_gallery, "Print PSLG gallery examples and mesh options.")

repl:register("pslg", pslg, "Build a named PSLG. Example: (pslg :cylinder {:radius 0.3})")
repl:register("mesh-pslg", mesh_pslg, "Build and mesh a named PSLG. Example: (mesh-pslg :cylinder {} {:resolution 0.05})")
repl:register("show-pslg", show_pslg_named, "Build and display a named PSLG. Example: (show-pslg :step)")
repl:register("show-mesh", show_mesh_named, "Build, mesh, and display a named PSLG. Example: (show-mesh :diffuser)")

repl:register("demo", demo, "No-argument demo: build, mesh, and display flow past a cylinder.")

repl:register("cylinder", cylinder, "Build flow past a circular cylinder PSLG.")
repl:register("square-cylinder", square_cylinder, "Build flow past a square cylinder PSLG.")
repl:register("wedge", triangle_wedge, "Build flow past a triangular wedge PSLG.")
repl:register("step", backward_facing_step, "Build a backward-facing step PSLG.")
repl:register("diffuser", diffuser, "Build a simple diffuser PSLG.")
repl:register("tee", mixing_tee, "Build a simple mixing tee PSLG.")
repl:register("plate", plate_with_baffle, "Build channel flow with an internal thin-plate baffle.")

print("Loaded PSLG gallery. Try (demo), (gallery), or (help-gallery).")

return repl:run()
