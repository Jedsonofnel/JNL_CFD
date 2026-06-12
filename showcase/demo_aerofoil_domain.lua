-- showcase/demo_aerofoil_domain.lua - NACA 4-digit aerofoil C-grid preview
-- <jed@nelson.ac> // 2026-06-12

local curve = require("jnl.geo2d.curve")
local mesh2d = require("jnl.mesh2d")
local ui = require("jnl.ui")
local repl = require("jnl.repl")

local FOIL = { m = 0.02, p = 0.4, t = 0.12 }

local R = 2.5
local L = 4.0

local NI = 65
local NJ = 33
local NW = 65

local function naca4_surfaces(m, p, t, n)
	local function thickness(x)
		return t / 0.2 * (
			0.2969 * math.sqrt(x)
			- 0.1260 * x
			- 0.3516 * x * x
			+ 0.2843 * x * x * x
			- 0.1036 * x * x * x * x
		)
	end

	local function camber(x)
		if m == 0 or p == 0 then
			return 0, 0
		end

		if x < p then
			return m / p / p * (2 * p * x - x * x),
				2 * m / p / p * (p - x)
		end

		local q = 1 - p
		return m / q / q * (1 - 2 * p + 2 * p * x - x * x),
			2 * m / q / q * (p - x)
	end

	local upper, lower = {}, {}

	for i = 0, n - 1 do
		local x = 0.5 * (1 - math.cos(math.pi * i / (n - 1)))
		local yt = thickness(x)
		local yc, dy = camber(x)
		local theta = math.atan(dy)

		upper[i + 1] = {
			x - yt * math.sin(theta),
			yc + yt * math.cos(theta),
		}

		lower[i + 1] = {
			x + yt * math.sin(theta),
			yc - yt * math.cos(theta),
		}
	end

	return upper, lower
end
local function build_grid()
	local E = mesh2d.edges

	local upper_pts, lower_pts =
		naca4_surfaces(FOIL.m, FOIL.p, FOIL.t, NI)

	local foil_pts = {}

	for i = NI, 1, -1 do
		foil_pts[#foil_pts + 1] = lower_pts[i]
	end

	for i = 2, NI do
		foil_pts[#foil_pts + 1] = upper_pts[i]
	end

	local foil = curve.through(foil_pts)

	local body_outer = curve.chain({
		curve.line(1, -R, 0, -R),
		curve.arc(0, 0, R, -math.pi / 2, -3 * math.pi / 2),
		curve.line(0, R, 1, R),
	})

	local lower_cut = curve.line(1, 0, 1, -R)
	local upper_cut = curve.line(1, 0, 1, R)

	local lower_outer = curve.line(1, -R, L, -R)
	local upper_outer = curve.line(1, R, L, R)
	local wake = curve.line(1, 0, L, 0)

	local lower_outlet = curve.line(L, -R, L, 0)
	local upper_outlet = curve.line(L, 0, L, R)

	local smooth = {
		max_iter = 2000,
		omega = 0.7,
		tol = 1e-10,
	}

	local g = mesh2d.grid()

	local body = g:block(2 * NI - 1, NJ, {
		tfi = true,
		smooth = smooth,
	})

	local lower_wake = g:block(NW, NJ, {
		tfi = true,
	})

	local upper_wake = g:block(NW, NJ, {
		tfi = true,
	})

	local normal_dist = curve.geom_start(1.08)

	body
		:south(foil, {
			dist = curve.cosine_both(),
		})
		:north(body_outer, {
			dist = curve.cosine_both(),
		})
		:west(lower_cut, {
			dist = normal_dist,
		})
		:east(upper_cut, {
			dist = normal_dist,
		})

	lower_wake
		:south(lower_outer, {
			dist = curve.geom_start(1.04),
		})
		:north(wake, {
			dist = curve.geom_start(1.04),
		})
		:east(lower_outlet, {
			-- lower outlet runs bottom -> centreline
			dist = curve.geom_end(1.08),
		})

	upper_wake
		:north(upper_outer, {
			dist = curve.geom_start(1.04),
		})
		:east(upper_outlet, {
			-- upper outlet runs centreline -> top
			dist = curve.geom_start(1.08),
		})

	g:join(body, E.W, lower_wake, E.W, true)
	g:join(body, E.E, upper_wake, E.W, false)
	g:join(lower_wake, E.N, upper_wake, E.S, false)

	return g
end

local function show()
	local domain, err = build_grid():to_domain()

	if not domain then
		print("to_domain failed: " .. tostring(err))
		return
	end

	ui.display_domain(domain)
end

local function show_mesh()
	local mesh, err = build_grid():build()

	if not mesh then
		print("build failed: " .. tostring(err))
		return
	end

	ui.display_mesh(mesh)
end

show_mesh()

print(
	"NACA 2412 three-block C-grid loaded. "
	.. "(show) for domain, (show-mesh) to redisplay mesh."
)

repl.register("show", show)
repl.register("show-mesh", show_mesh)
repl.run()
