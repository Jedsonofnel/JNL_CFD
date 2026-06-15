-- test/fvm/pressure_correction_test.lua
-- <jed@nelson.ac> // 2026-06-15
--
-- Validates SIMPLE pressure-velocity coupling physics in isolation.
--
-- Uses direct binding calls (B.*) rather than the compiled dispatch path so
-- that physics bugs and compiler sign bugs are separated cleanly.
--
-- The critical diagnostic is the "source sign" group: one of the two scale
-- tests must reduce divergence and the other must amplify it. Which is which
-- tells you whether the Nabla compiler emits the correct scale for the p'
-- equation.
--
-- Convention reminder: in the JNL FVM assembly,
--   su_i_fs(scale, src)  ->  b_P += scale * src_P
--   a_P phi - sum(a_nb phi_nb) = b_P  represents  nabla.(gamma nabla phi) = -b_P / V_P
-- Therefore  laplacian:equals(-f)  implements  L phi = f  (note the negation).
-- Momentum uses equals(-grad_p) correctly; p' must use equals(-div(mwi)).

local h      = require("test.harness")
local preset = require("jnl.fvm.preset")
local cart   = require("jnl.mesh2d.cartesian")
local bc     = require("jnl.fvm.bc")
local Case   = require("jnl.fvm.case")
local B      = require("jnl.fvm.bindings")
local E      = require("jnl.mesh2d.edges")
local P      = E.PATCH

--
-- Parameters: match C reference so diagonal estimates are comparable.
--

local NX     = 20
local NY     = 20
local NU     = 0.01

--
-- Fixture construction
--

local function make_mesh()
	return assert(cart.build(1.0, 1.0, NX, NY))
end

local function make_bcs()
	return bc.new_set()
		:vector("U")
		:on(P.SOUTH, bc.no_slip())
		:on(P.NORTH, bc.moving_wall(1, 0))
		:on(P.EAST, bc.outlet())
		:on(P.WEST, bc.outlet())
		:scalar("p")
		:all(bc.nograd())
		:scalar("p_prime")
		:all(bc.nograd())
		:build()
end

local function make_case(mesh, bcs)
	local reg = preset.reg.stokes({ nu = NU })
	local alg = preset.alg.simple()
	local c   = Case.new(reg, alg, mesh, bcs)
	c:allocate()
	return c
end

--
-- Ghost-fill helpers
--

local function fill_U_ghosts(mesh, ux, uy)
	B.patch_v_fill_d(mesh, ux, uy, "south", 0.0, 0.0)
	B.patch_v_fill_d(mesh, ux, uy, "north", 1.0, 0.0)
	B.patch_v_fill_n(mesh, ux, uy, "east", 0.0, 0.0)
	B.patch_v_fill_n(mesh, ux, uy, "west", 0.0, 0.0)
end

local function fill_s_ghosts(mesh, phi)
	B.patch_s_fill_n(mesh, phi, "north", 0.0)
	B.patch_s_fill_n(mesh, phi, "south", 0.0)
	B.patch_s_fill_n(mesh, phi, "east", 0.0)
	B.patch_s_fill_n(mesh, phi, "west", 0.0)
end

local function close_neumann_all(sys, mesh)
	B.patch_s_close_n(sys, mesh, "north", 0.0)
	B.patch_s_close_n(sys, mesh, "south", 0.0)
	B.patch_s_close_n(sys, mesh, "east", 0.0)
	B.patch_s_close_n(sys, mesh, "west", 0.0)
end

--
-- Field setup helpers
--

-- Plant Ux = y + eps*sin(2pi*x), Uy = 0.
--
-- The sinusoidal perturbation gives dUx/dx = eps*2pi*cos(2pi*x), which
-- integrates to zero over [0,1] so the source for the p' Poisson is
-- compatible with the all-Neumann BCs (zero net flux).
-- eps=0 gives the exact divergence-free Couette profile.
local function plant_velocity(c, mesh, eps)
	eps      = eps or 0.0
	local nr = mesh:n_real_cells()
	local cx = mesh:cell_cx_vec()
	local cy = mesh:cell_cy_vec()
	local ux = c.field_map["U_x"]
	local uy = c.field_map["U_y"]
	for i = 1, nr do
		ux[i] = cy[i] + eps * math.sin(2.0 * math.pi * cx[i])
		uy[i] = 0.0
	end
	fill_U_ghosts(mesh, ux, uy)
end

-- Seed diagonal and inv_d with constant physically-scaled values.
--
-- For a 1x1 domain with nu=0.01, the momentum diagonal is approximately
-- nu * 4 * (face_area / face_dist) = 4*nu for a uniform Cartesian mesh.
-- Ghost cells receive the same constant so Rhie-Chow face interpolation
-- of the diagonal remains well-conditioned at boundaries.
local function plant_diag(c, mesh, ap_override)
	local ap     = ap_override or (4.0 * NU)
	local ntotal = mesh:n_total_cells()
	local nreal  = mesh:n_real_cells()
	local vol    = mesh:cell_vol_vec()
	local dx     = c.field_map["diag_U_x"]
	local dy     = c.field_map["diag_U_y"]
	local inv_d  = c.field_map["inv_d"]
	for i = 1, ntotal do
		dx[i] = ap
		dy[i] = ap
	end
	for i = 1, nreal do
		inv_d[i] = vol[i] * 2.0 / (ap + ap)
	end
	B.ghost_copy(mesh, inv_d)
end

--
-- Pressure correction sequence (direct bindings, no compiled dispatch).
--
-- Returns div_before_l2 and div_after_l2, the integrated divergence L2
-- norms before and after one SIMPLE pressure-velocity correction step.
-- Operates on c.field_map in-place.
--
-- scale controls the sign of the p' source:
--   -1.0 => laplacian:equals(-divU)  => correct SIMPLE
--   +1.0 => laplacian:equals(+divU)  => wrong sign
--
local function run_pressure_correction(c, mesh, scale)
	scale       = scale or -1.0
	local m     = c.field_map
	local nr    = mesh:n_real_cells()

	-- Allocate temporary gradient fields if not already present.
	-- (They will be in the manifest for a stokes case; this guards
	-- against a manually constructed test case that lacks them.)
	local gx_p  = m["grad_p_x"] or m["__tmp_gx_p"]
	local gy_p  = m["grad_p_y"] or m["__tmp_gy_p"]
	local gx_pp = m["grad_p_prime_x"] or m["__tmp_gx_pp"]
	local gy_pp = m["grad_p_prime_y"] or m["__tmp_gy_pp"]
	local mwi   = m["mwi_U_p"] or m["__tmp_mwi"]
	local divU  = m["__mwidiv_mwi_U_p"] or m["__tmp_divU"]

	assert(gx_p and gy_p, "missing grad_p fields in field_map")
	assert(gx_pp and gy_pp, "missing grad_p_prime fields in field_map")
	assert(mwi, "missing mwi_U_p face field in field_map")
	assert(divU, "missing __mwidiv_mwi_U_p cell field in field_map")

	-- 1. Pressure gradient on current p (all zeros initially).
	fill_s_ghosts(mesh, m["p"])
	B.grad_gg(mesh, m["p"], gx_p, gy_p)

	-- 2. Rhie-Chow face flux.
	fill_U_ghosts(mesh, m["U_x"], m["U_y"])
	B.rhie_chow(mesh,
		m["U_x"], m["U_y"], m["p"],
		gx_p, gy_p,
		m["diag_U_x"], m["diag_U_y"],
		mwi)

	-- 3. Integrated divergence: sum(flux * A) per cell, units [m^3/s].
	B.divergence_i(mesh, mwi, divU)
	local div_before_l2 = divU:norm_l2()

	-- 4. Assemble and solve p' Poisson.
	m["p_prime"]:fill(0.0)
	fill_s_ghosts(mesh, m["p_prime"])

	local pp_sys = c.sys_map["p_prime"]
	pp_sys:reset()
	B.laplacian_f(pp_sys, mesh, m["inv_d"])
	-- scale=-1: b += -divU  =>  L p' = +divU  (correct)
	-- scale=+1: b += +divU  =>  L p' = -divU  (wrong; amplifies divergence)
	B.su_i_fs(pp_sys, mesh, scale, divU)
	close_neumann_all(pp_sys, mesh)

	local pp_real = c.ctx:real_view_of(m["p_prime"])
	local solver = pp_sys:cg_dic(pp_real, 1e-8)
	for _ = 1, 2000 do
		local st = solver:iter()
		if st.done or st.breakdown then break end
	end
	solver:finish_change_into(pp_real)

	-- 5. Gradient of p'.
	fill_s_ghosts(mesh, m["p_prime"])
	B.grad_gg(mesh, m["p_prime"], gx_pp, gy_pp)

	-- 6. Velocity correction: U** = U* - (vol/diag) * grad(p').
	local vol = mesh:cell_vol_vec()
	local ux  = m["U_x"]
	local uy  = m["U_y"]
	for i = 1, nr do
		ux[i] = ux[i] - vol[i] * gx_pp[i] / m["diag_U_x"][i]
		uy[i] = uy[i] - vol[i] * gy_pp[i] / m["diag_U_y"][i]
	end
	fill_U_ghosts(mesh, ux, uy)

	-- 7. Recompute Rhie-Chow and divergence after correction.
	fill_s_ghosts(mesh, m["p"])
	B.grad_gg(mesh, m["p"], gx_p, gy_p)
	B.rhie_chow(mesh,
		m["U_x"], m["U_y"], m["p"],
		gx_p, gy_p,
		m["diag_U_x"], m["diag_U_y"],
		mwi)
	B.divergence_i(mesh, mwi, divU)
	local div_after_l2 = divU:norm_l2()

	return div_before_l2, div_after_l2
end

-- Convenience: fresh case, plant velocity and diagonal, run one correction.
local function correction_run(eps, scale, ap_override)
	local mesh = make_mesh()
	local bcs  = make_bcs()
	local c    = make_case(mesh, bcs)
	plant_velocity(c, mesh, eps)
	plant_diag(c, mesh, ap_override)
	return run_pressure_correction(c, mesh, scale)
end

--
-- Tests
--

h.describe("pressure correction: null test (exact Couette input)", function()
	h.it("divergence is near-zero before correction on exact profile", function()
		local div_before, _ = correction_run(0.0, -1.0)
		h.expect(div_before).is_less_than(1e-8,
			"div_before on exact profile: " .. tostring(div_before))
	end)

	h.it("p' is near-zero when input is exactly divergence-free", function()
		local mesh = make_mesh()
		local bcs  = make_bcs()
		local c    = make_case(mesh, bcs)
		plant_velocity(c, mesh, 0.0)
		plant_diag(c, mesh)
		run_pressure_correction(c, mesh, -1.0)
		local pp_inf = c.field_map["p_prime"]:norm_linf()
		h.expect(pp_inf).is_less_than(1e-8,
			"p' on exact profile: expected near-zero, got " .. tostring(pp_inf))
	end)

	h.it("divergence after correction is not larger than before on exact profile", function()
		local div_before, div_after = correction_run(0.0, -1.0)
		h.expect(div_after).is_less_than(div_before + 1e-12,
			string.format("div grew on exact profile: before=%.4e after=%.4e",
				div_before, div_after))
	end)
end)

h.describe("pressure correction: source sign diagnostic", function()
	-- This is the key diagnostic for the preset.lua sign question.
	--
	-- With eps=0.05 the input velocity field has a non-trivial integrated
	-- divergence (~eps * 2pi * cell_vol per cell). One correction step with
	-- the correct sign should reduce that divergence; the wrong sign amplifies
	-- it by feeding back positively.
	--
	-- If scale=-1 fails and scale=+1 passes, the sign in preset.lua is wrong.
	-- If both fail, something else is broken (inv_d, Rhie-Chow, or the solver).

	h.it("scale=-1 reduces divergence (correct SIMPLE convention)", function()
		local div_before, div_after = correction_run(0.05, -1.0)
		h.expect(div_after).is_less_than(div_before,
			string.format(
				"scale=-1 should reduce divergence: before=%.4e after=%.4e",
				div_before, div_after))
	end)

	h.it("scale=+1 amplifies divergence (confirms sign convention)", function()
		local div_before, div_after = correction_run(0.05, 1.0)
		h.expect(div_after).is_greater_than(div_before,
			string.format(
				"scale=+1 should amplify divergence: before=%.4e after=%.4e",
				div_before, div_after))
	end)
end)

h.describe("pressure correction: diagonal scaling", function()
	-- inv_d = cV * 2 / (diag_x + diag_y).
	-- A stiffer momentum matrix (large ap, e.g. high Re) gives smaller inv_d
	-- and a weaker diffusion coefficient in the p' Poisson. The velocity
	-- correction U -= (vol/ap)*grad(p') is also smaller. The combined effect
	-- should still reduce divergence, just less aggressively.

	h.it("correction still reduces divergence for 10x stiffer diagonal", function()
		local div_before, div_after = correction_run(0.05, -1.0, 4.0 * NU * 10.0)
		h.expect(div_after).is_less_than(div_before,
			string.format(
				"stiff diagonal: before=%.4e after=%.4e",
				div_before, div_after))
	end)

	h.it("correction still reduces divergence for 10x softer diagonal", function()
		local div_before, div_after = correction_run(0.05, -1.0, 4.0 * NU * 0.1)
		h.expect(div_after).is_less_than(div_before,
			string.format(
				"soft diagonal: before=%.4e after=%.4e",
				div_before, div_after))
	end)
end)
