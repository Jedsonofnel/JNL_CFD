-- jnl/fvm/canned.lua - Canned registries/algorithms for common CFD
-- <jed@nelson.ac> // 2026-05-23

local A = require("jnl.core.algorithm")
local E = require("jnl.core.expr")
local R = require("jnl.core.registry")

local FVM = require("jnl.fvm")
local Op = FVM.Op
local FVMe = FVM.Expr

local BC = require("jnl.fvm.bc")

local rules = require("jnl.fvm.rules")

local M = {}

--
-- Registries
--

function M.incompressible_registry(props)
	props         = props or {}
	local rho     = props.rho or 1.0
	local mu      = props.mu or 1e-3
	local alpha_p = props.alpha_p or 0.3

	local reg     = R.new()
	reg:constant("rho", rho)
	reg:constant("mu", mu)
	reg:constant("alpha_p", alpha_p)

	reg:field("Ux", {
		eq = FVM.eq(
			Op.div(FVMe.mwi("U", "p"), "Ux"),
			Op.lap("mu", "Ux"),
			Op.su(E.neg(FVMe.grad("p", "x"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:field("Uy", {
		eq = FVM.eq(
			Op.div(FVMe.mwi("U", "p"), "Uy"),
			Op.lap("mu", "Uy"),
			Op.su(E.neg(FVMe.grad("p", "y"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:vector("U", { "Ux", "Uy" })

	reg:expression("divU", FVMe.div_mwi("U", "p"))

	reg:expression("inv_d",
		E.mul(E.cV(), E.div(2, E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))

	reg:field("p", {
		eq = FVM.eq(
			Op.lap("inv_d", "p"),
			{ relax = 0.3, solver = "cg" }
		)
	})

	local pp = E.prime_name("p")
	reg:field(pp, {
		eq = FVM.eq(
			Op.lap("inv_d", pp),
			Op.su(E.neg("divU")),
			{ solver = "cg" }
		),
		bcs = { BC.neumann_all(0.0) },
	})

	reg:correction("Ux", E.sub(E.expl("Ux"),
		E.mul(E.cV(), E.div(FVMe.grad(pp, "x"), FVMe.diag("Ux")))))
	reg:correction("Uy", E.sub(E.expl("Uy"),
		E.mul(E.cV(), E.div(FVMe.grad(pp, "y"), FVMe.diag("Uy")))))
	reg:correction("p", E.add(E.expl("p"),
		E.mul("alpha_p", E.prime("p"))))

	return reg
end

function M.stokes_registry(props)
	props         = props or {}
	local mu      = props.mu or 1e-3
	local alpha_p = props.alpha_p or 0.3
	local reg     = R.new()

	reg:constant("mu", mu)
	reg:constant("alpha_p", alpha_p)

	reg:field("Ux", {
		eq = FVM.eq(
			Op.lap("mu", "Ux"),
			Op.su(E.neg(FVMe.grad("p", "x"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:field("Uy", {
		eq = FVM.eq(
			Op.lap("mu", "Uy"),
			Op.su(E.neg(FVMe.grad("p", "y"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:vector("U", { "Ux", "Uy" })

	reg:expression("divU", FVMe.div_mwi("U", "p"))

	reg:expression("inv_d",
		E.mul(E.cV(), E.div(2, E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))

	reg:field("p", {
		eq = FVM.eq(
			Op.lap("inv_d", "p"),
			{ relax = 0.3, solver = "cg" }
		)
	})

	local pp = E.prime_name("p")
	reg:field(pp, {
		eq = FVM.eq(
			Op.lap("inv_d", pp),
			Op.su(E.neg("divU")),
			{ solver = "cg" }
		),
		bcs = { BC.neumann_all(0.0) },
	})

	reg:correction("Ux", E.sub(E.expl("Ux"),
		E.mul(E.cV(), E.div(FVMe.grad(pp, "x"), FVMe.diag("Ux")))))
	reg:correction("Uy", E.sub(E.expl("Uy"),
		E.mul(E.cV(), E.div(FVMe.grad(pp, "y"), FVMe.diag("Uy")))))
	reg:correction("p", E.add(E.expl("p"),
		E.mul("alpha_p", E.prime("p"))))

	return reg
end

--
-- Convergence rulesets
--

M.SIMPLEConvergence = rules.stopping({
	converged = rules.all_fields({
		Ux = rules.residual_below(1e-4, 3),
		Uy = rules.residual_below(1e-4, 3),
		p  = rules.residual_below(1e-4, 3),
	}),
	diverged = rules.any_field({
		Ux = rules.field_above(1e15),
		Uy = rules.field_above(1e15),
		p  = rules.any_of(rules.field_above(1e15), rules.field_is_nan()),
	}),
})

--
-- Algorithms
--

function M.SIMPLE(opts)
	opts = opts or {}
	local alg = A.new()
	alg:loop(function(a)
		a:solve("U")
		a:solve("p")
		a:monitor("divU")
		a:zero(E.prime_name("p"))
		a:solve(E.prime_name("p"))
		a:correct("U")
		a:correct("p")
	end, {
		max_iters = opts.max_iters or 1000,
		linalg_max_iters = opts.linalg_max_iters or 20,
	})
	-- alg:add_ruleset(M.SIMPLEConvergence)
	alg:add_ruleset(M.SIMPLEPostMortem)
	return alg
end

--
-- Other rulesets
--

local function field_history(sage, field, kind, n)
	return sage:cache_query(rules.BY_FIELD_KEY, field .. ":" .. kind,
		{ sort_by = "iter", desc = true, limit = n })
end

M.SIMPLEPostMortem = rules.post_mortem({
	rules.pm_rule("nan", function(_, f, d, diag)
		if not d then return end
		for _, name in ipairs({ "Ux", "Uy", "p" }) do
			if d.is_nan(name) then
				diag("nan_in_" .. name, "NaN in " .. name
					.. " at iter " .. f.iter)
			end
		end
	end),
	rules.pm_rule("divu_check", function(sage, f, d, diag)
		if not d then return end
		local divu_max = d.max("divU")
		io.write(string.format("[POST-MORTEM]  divU max = %.3e\n", divu_max))
		if divu_max ~= divu_max then
			diag("divu_nan", "divU is NaN from iteration 0 — MWI flux uninitialised")
		end
	end),
	rules.pm_rule("pressure_singular", function(sage, _, _, diag)
		local h = field_history(sage, "p", "field_norm", 999)
		if #h < 3 then return end
		local mono = true
		for i = 2, #h do
			if h[i].value < h[i - 1].value then
				mono = false; break
			end
		end
		if mono then
			diag("pressure_singular",
				"p norm grew monotonically every iter")
		end
	end),
	rules.pm_rule("velocity_blowup", function(sage, f, _, diag)
		local h = field_history(sage, "Ux", "field_norm", 1)
		if h[1] and h[1].value > 1e10 then
			diag("velocity_blowup",
				string.format("Ux = %.2e at iter %d", h[1].value, f.iter))
		end
	end),
	rules.pm_rule("stalled_residuals", function(sage, _, _, diag)
		local h = field_history(sage, "Ux", "residual", 5)
		if #h < 5 then return end
		local all_large = true
		for _, e in ipairs(h) do
			if e.value < 0.1 then
				all_large = false; break
			end
		end
		if all_large then
			diag("stalled_residuals",
				"Ux residuals > 0.1 for 5 iters")
		end
	end),
	rules.pm_rule("matrix_health", function(_, _, d, diag)
		if not d then return end
		for _, name in ipairs({ "Ux", "Uy", "p" }) do
			local s = d.sys_diag(name)
			if not s then goto continue end
			if not s.all_diagonals_positive then
				diag("negative_diagonal_" .. name,
					string.format("%s: non-positive diagonal entries — operator sign error or BC issue", name))
			end
			if s.diagonal_dominance < 0 then
				diag("diagonal_not_dominant_" .. name,
					string.format("%s: diagonal dominance = %.3e — matrix likely singular", name, s.diagonal_dominance))
			end
			if s.max_asymmetry > 1e-6 then
				diag("asymmetry_" .. name,
					string.format("%s: max asymmetry = %.3e — UDS/TVD correction may be too large", name, s
						.max_asymmetry))
			end
			::continue::
		end
	end),
	rules.pm_rule("residual_trajectory", function(sage, _, _, diag)
		for _, name in ipairs({ "Ux", "Uy", "p" }) do
			local h = field_history(sage, name, "residual", 10)
			if #h < 2 then goto continue end
			-- print trajectory regardless, useful context
			local traj = {}
			for i = #h, 1, -1 do
				traj[#traj + 1] = string.format("%.2e", h[i].value)
			end
			io.write(string.format("[POST-MORTEM]  %s residuals: %s\n",
				name, table.concat(traj, " -> ")))
			-- check if growing
			local growing = h[1].value > h[#h].value * 10
			if growing then
				diag("residual_growing_" .. name,
					string.format("%s: residual grew %.1fx over last %d iters",
						name, h[1].value / (h[#h].value + 1e-300), #h))
			end
			::continue::
		end
	end),
	rules.pm_rule("diagonal_range", function(_, _, d, _)
		if not d then return end
		for _, name in ipairs({ "Ux", "Uy", "p" }) do
			local s = d.sys_diag(name)
			if not s then goto continue end
			io.write(string.format(
				"[POST-MORTEM]  %s: diag_dominance=%.3e  all_pos=%s  residual=%.3e\n",
				name,
				s.diagonal_dominance,
				tostring(s.all_diagonals_positive),
				s.residual_norm))
			::continue::
		end
	end),
	rules.pm_advice("pressure_singular",
		"Pin a cell: add sys:pin_cell(1, 0.0) or a Dirichlet p BC"),
	rules.pm_advice("velocity_blowup",
		"Reduce relaxation (try alpha_u=0.3) or check BCs"),
	rules.pm_advice("stalled_residuals",
		"Reduce velocity under-relaxation below 0.5"),
	rules.pm_advice("nan_in_p",
		"Pressure went NaN — likely singular system, pin a cell"),
})

return M
