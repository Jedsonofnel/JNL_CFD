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

study:defaults({
	pe = 10.0,
	nx = 50,
	scheme = "uds",
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
		local x, y = res.mesh:cell_centre(i)
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

study:expose("plot-comparison", function()
	local res = study:result_or_run()
	local num_prof = get_profile(res)
	local exact_prof = get_analytical_profile(res.opts.pe)

	compare.show(num_prof, exact_prof, {
		title = "1D Convection-Diffusion (Pe = " .. res.opts.pe .. ")",
		xlabel = "x",
		ylabel = "phi"
	})
end, "Plot the result against the analytical solution")

study:expose("save-comparison", function(path)
	if type(path) ~= "string" or path == "" then
		return print("Error: save-comparison requires a mandatory string path argument (e.g., \"output.png\")")
	end

	local res = study:result_or_run()
	local num_prof = get_profile(res)
	local exact_prof = get_analytical_profile(res.opts.pe)

	compare.save(path, num_prof, exact_prof, {
		title = "1D Convection-Diffusion (Pe = " .. res.opts.pe .. ")",
		xlabel = "x",
		ylabel = "phi"
	})
	print("Saved comparison plot to " .. path)
end, "Save the gnuplot comparison to the specified path")

study:expose("demo", function()
	print("Running default UDS comparison demo...")

	local res = study:run({ scheme = "uds", pe = 10.0 })
	local num_prof = get_profile(res)
	local exact_prof = get_analytical_profile(res.opts.pe)

	compare.show(num_prof, exact_prof, {
		title = "Demo: UDS 1D Convection-Diffusion",
		xlabel = "x",
		ylabel = "phi"
	})
end, "Run a quick demo showing UDS comparison")

print("\nLoad complete. Try calling (demo)")
print("Or run (run {:scheme \"cds\" :pe 20.0}) then (plot-comparison) or (save-comparison \"out.png\")\n")

return study:repl()
