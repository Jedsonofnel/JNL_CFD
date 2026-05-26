-- lua/showcase/validate_conv_diff.lua - Convection-diffusion scheme validation
-- <jed@nelson.llm> // 2026-05-26

local fvm = require("jnl.fvm")
local mesh2d = require("jnl.mesh2d")
local compare = require("jnl.gp.compare")
local study = require("jnl.fvm.study").new("Validation: Convection-Diffusion")

--
-- Defaults
--

study:about([[
Validates UDS and CDS advection schemes against the analytical 1D convection-diffusion solution.
Provides gnuplot comparison and PNG export.
]])

study:design({
	pe     = 10.0,
	scheme = "uds",
})

study:defaults({
	nx = 50,
})

--
-- Geometry and mesh
--

study:mesh(function(_, o)
	return mesh2d.new_smesh(1.0, 0.1, o.nx, 1)
end)

--
-- Physics
--

study:registry(function(_, o)
	local reg = require("jnl.core.registry").new()
	local E = fvm.Expr
	local Op = fvm.Op

	reg:constant("rho", 1.0)
	reg:constant("Gamma", 1.0 / o.pe)

	reg:uniform("Ux", 1.0)
	reg:uniform("Uy", 0.0)
	reg:vector("U", { "Ux", "Uy" })

	reg:field("phi", {
		eq = fvm.eq(
			Op.div(E.face_normal("U"), "phi", { scheme = o.scheme }),
			Op.lap("Gamma", "phi")
		),
		initial = 0.0
	})

	return reg
end)

--
-- Algorithm
--

study:algorithm(function()
	local alg = require("jnl.fvm.algorithm").new()
	alg:linear(function(b)
		b:solve("phi")
	end)
	return alg
end)

--
-- Boundary conditions
--

study:bcs(function()
	local bc = require("jnl.fvm.bc")
	return {
		phi = {
			bc.dirichlet("west", 0.0),
			bc.dirichlet("east", 1.0),
			bc.symmetry("south"),
			bc.symmetry("north")
		}
	}
end)

--
-- Validation data
--

local function analytical_solution(x, pe)
	if pe == 0.0 then
		return x
	end
	return (math.exp(pe * x) - 1.0) / (math.exp(pe) - 1.0)
end

local function get_profile(res)
	local xs = {}
	local phis = {}
	local phi_field = res.field("phi")

	for i = 1, res.mesh:n_cells() do
		local x, _ = res.mesh:cell_centre(i)
		table.insert(xs, x)
		table.insert(phis, phi_field[i])
	end

	return compare.profile(xs, phis, { label = string.upper(res.opts.scheme) .. " Numeric" })
end

local function get_analytical_profile(pe)
	local xs = {}
	local phis = {}

	for i = 0, 100 do
		local x = i / 100.0
		table.insert(xs, x)
		table.insert(phis, analytical_solution(x, pe))
	end

	return compare.profile(xs, phis, { label = "Analytical (Pe=" .. pe .. ")" })
end

--
-- Outputs and entry points
--

study:output("numeric-profile", function(res)
	return get_profile(res)
end, "Return the numeric phi profile")

study:output("analytical-profile", function(res)
	return get_analytical_profile(res.opts.pe)
end, "Return the analytical phi profile")

study:plot("comparison", function(res)
	compare.show(get_profile(res), get_analytical_profile(res.opts.pe), {
		title  = "1D Convection-Diffusion (Pe = " .. res.opts.pe .. ")",
		xlabel = "x",
		ylabel = "phi",
	})
end, { doc = "Plot numeric result against analytical solution" })

study:write("comparison", function(res, path)
	compare.save(path, get_profile(res), get_analytical_profile(res.opts.pe), {
		title  = "1D Convection-Diffusion (Pe = " .. res.opts.pe .. ")",
		xlabel = "x",
		ylabel = "phi",
	})
	print("Saved to " .. path)
end, { doc = "Save comparison plot to path (default: conv_diff.png)" })

--
-- Peclet Sweep
--

local function result_error(res)
	local num   = get_profile(res)
	local exact = get_analytical_profile(res.opts.pe)
	local comp  = compare.sample_at_reference(num, exact)
	return compare.error_norms(comp)
end

local function run_pe_sweep(s)
	local pe_values = { 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 400.0 }
	local results   = {}
	for _, scheme in ipairs({ "uds", "cds" }) do
		results[scheme] = { pe = {}, l2 = {}, linf = {} }
		for _, pe in ipairs(pe_values) do
			local res           = s:run({ pe = pe, scheme = scheme })
			local errs          = result_error(res)
			local t             = results[scheme]
			t.pe[#t.pe + 1]     = pe
			t.l2[#t.l2 + 1]     = errs.l2
			t.linf[#t.linf + 1] = errs.linf
		end
	end
	return results
end

local function plot_pe_sweep(sweep_results)
	local gp  = require("jnl.gp")
	local fig = gp.figure({
		title  = "Pe sweep: L2 error vs Peclet number",
		xlabel = "Pe",
		ylabel = "L2 error",
		logx   = true,
		logy   = true,
		grid   = true,
	})
	for _, scheme in ipairs({ "uds", "cds" }) do
		local t = sweep_results[scheme]
		fig:add(t.pe, t.l2, { title = string.upper(scheme) })
	end
	fig:show()
end

study:sweep("pe-sweep", run_pe_sweep,
	{ doc = "Sweep Pe for UDS and CDS and return error tables" })

study:expose("plot-pe-sweep", function()
	plot_pe_sweep(run_pe_sweep(study))
end, "Run Pe sweep and plot L2 error vs Pe")

--
-- Final plot
--

local function plot_scheme_comparison(pe)
	pe               = pe or 10.0
	local gp         = require("jnl.gp")

	local uds_res    = study:run({ pe = pe, scheme = "uds" })
	local cds_res    = study:run({ pe = pe, scheme = "cds" })

	local uds_prof   = get_profile(uds_res)
	local cds_prof   = get_profile(cds_res)
	local exact_prof = get_analytical_profile(pe)

	local uds_errs   = result_error(uds_res)
	local cds_errs   = result_error(cds_res)

	local fig        = gp.figure({
		title  = string.format(
			"Convection-Diffusion Pe=%.0f  |  UDS L2=%.2e  CDS L2=%.2e",
			pe, uds_errs.l2, cds_errs.l2),
		xlabel = "x",
		ylabel = "phi",
		grid   = true,
	})

	fig:add(exact_prof.coord, exact_prof.value, {
		title = "Analytical",
		style = "lines",
		lw    = 2,
	})
	fig:add(uds_prof.coord, uds_prof.value, {
		title = "UDS",
		style = "points",
		pt    = 7,
		ps    = 0.8,
	})
	fig:add(cds_prof.coord, cds_prof.value, {
		title = "CDS",
		style = "points",
		pt    = 5,
		ps    = 0.8,
	})

	fig:show()
end

study:expose("plot-schemes", function(pe)
	plot_scheme_comparison(pe)
end, "Plot UDS, CDS, and analytical at given Pe (default 10)")

study:write("schemes", function(res, path)
	local pe       = res.opts.pe
	local uds_res  = study:run({ pe = pe, scheme = "uds" })
	local cds_res  = study:run({ pe = pe, scheme = "cds" })
	local uds_errs = result_error(uds_res)
	local cds_errs = result_error(cds_res)
	local gp       = require("jnl.gp")
	local fig      = gp.figure({
		title  = string.format(
			"Convection-Diffusion Pe=%.0f  |  UDS L2=%.2e  CDS L2=%.2e",
			pe, uds_errs.l2, cds_errs.l2),
		xlabel = "x",
		ylabel = "phi",
		grid   = true,
	})
	fig:add(get_analytical_profile(pe).coord, get_analytical_profile(pe).value,
		{ title = "Analytical", style = "lines", lw = 2 })
	fig:add(get_profile(uds_res).coord, get_profile(uds_res).value,
		{ title = "UDS", style = "points", pt = 7, ps = 0.8 })
	fig:add(get_profile(cds_res).coord, get_profile(cds_res).value,
		{ title = "CDS", style = "points", pt = 5, ps = 0.8 })
	fig:save(path)
	print("Saved to " .. path)
end, { doc = "Save UDS/CDS/analytical comparison to path" })

return study:repl()
