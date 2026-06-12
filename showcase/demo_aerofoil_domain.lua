-- showcase/demo_aerofoil_domain.lua - NACA 4-digit aerofoil C-block domain preview
-- <jed@nelson.ac> // 2026-06-12

local curve = require("jnl.geo2d.curve")
local mesh2d = require("jnl.mesh2d")
local ui = require("jnl.ui")
local repl = require("jnl.repl")

--
-- Parameters
--

-- NACA 2412
local FOIL = { m = 0.02, p = 0.4, t = 0.12 }

local R = 2.5 -- far-field radius, centred at LE
local L = 4.0 -- wake exit x-coordinate
local NI = 65 -- points per aerofoil surface half (cosine-clustered)
local NJ = 33 -- wall-normal points

--
-- NACA 4-digit aerofoil
--

-- Closed-TE Ladson modification (last coefficient -0.1036 gives yt(1) = 0).
local function naca4_surfaces(m, p, t, n)
	local function thickness(x)
		return t / 0.2 * (0.2969 * math.sqrt(x) - 0.1260 * x
			- 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)
	end
	local function camber(x)
		if m == 0 or p == 0 then return 0, 0 end
		if x < p then
			return m / p / p * (2 * p * x - x * x), 2 * m / p / p * (p - x)
		end
		local q = 1 - p
		return m / q / q * (1 - 2 * p + 2 * p * x - x * x), 2 * m / q / q * (p - x)
	end
	local upper, lower = {}, {}
	for i = 0, n - 1 do
		local x      = 0.5 * (1 - math.cos(math.pi * i / (n - 1)))
		local yt     = thickness(x)
		local yc, dy = camber(x)
		local th     = math.atan(dy)
		upper[i + 1] = { x - yt * math.sin(th), yc + yt * math.cos(th) }
		lower[i + 1] = { x + yt * math.sin(th), yc - yt * math.cos(th) }
	end
	return upper, lower
end

--
-- Single-block C-mesh
--

local function build_grid()
	local pi = math.pi
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

	local far_field = curve.chain({
		curve.line(L, 0, L, -R),
		curve.line(L, -R, 0, -R),
		curve.arc(0, 0, R, -pi / 2, -3 * pi / 2),
		curve.line(0, R, L, R),
		curve.line(L, R, L, 0),
	})

	local wake = curve.line(1, 0, L, 0)

	local g = mesh2d.grid()
	local b = g:block(#foil_pts, NJ, {
		tfi = true,
	})

	b:south(curve.through(foil_pts), {
		dist = curve.cosine_both(),
	})
		:north(far_field, {
			dist = curve.cosine_both(),
		})
		:west(wake)

	-- Populate EAST by copying WEST, then stitch the corresponding vertices.
	g:join(b, E.W, b, E.E)

	return g
end

--
-- Entry points
--

local function show()
	local g = build_grid()
	local d, err = g:to_domain()
	if not d then
		print("to_domain failed: " .. tostring(err))
		return
	end
	ui.display_domain(d)
end

local function show_mesh()
	local g = build_grid()
	local mesh, err = g:build()
	if not mesh then
		print("build failed: " .. tostring(err))
		return
	end
	ui.display_mesh(mesh)
end

show()
print("NACA 2412 C-block loaded.  (show) to redisplay, (show-mesh) for full mesh.")

repl.register("show", show)
repl.register("show-mesh", show_mesh)
repl.run()
