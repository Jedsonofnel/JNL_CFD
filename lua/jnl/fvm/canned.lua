-- jnl/fvm/canned.lua - Canned registries/algorithms for common CFD
-- <jed@nelson.ac> // 2026-05-23

local A     = require("jnl.core.algorithm")
local E     = require("jnl.core.expr")
local R     = require("jnl.core.registry")
local FVM   = require("jnl.fvm")
local Op    = FVM.Op
local FVMe  = FVM.Expr
local BC    = require("jnl.fvm.bc")
local rules = require("jnl.fvm.rules")

local M     = {}


M._doc = "Canned registries and algorithms for common incompressible CFD problems."

--
-- REGISTRIES
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
	reg:field("p")

	local pp = E.prime_name("p")
	reg:field(pp, {
		eq = FVM.eq(
			Op.lap("inv_d", pp),
			Op.su(E.neg("divU"), { integrated = true }),
			{ solver = "cg" }
		),
		bcs = { BC.neumann_all(0.0) },
	})

	reg:correction("Ux", E.neg(
		E.mul(E.cV(), E.div(FVMe.grad(pp, "x"), FVMe.diag("Ux")))))
	reg:correction("Uy", E.neg(
		E.mul(E.cV(), E.div(FVMe.grad(pp, "y"), FVMe.diag("Uy")))))
	reg:correction("p", E.mul("alpha_p", E.prime("p")))

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
	reg:field("p")

	local pp = E.prime_name("p")
	reg:field(pp, {
		eq = FVM.eq(
			Op.lap("inv_d", pp),
			Op.su(E.neg("divU"), { integrated = true }),
			{ solver = "cg" }
		),
		bcs = { BC.neumann_all(0.0) },
	})

	reg:correction("Ux", E.neg(
		E.mul(E.cV(), E.div(FVMe.grad(pp, "x"), FVMe.diag("Ux")))))
	reg:correction("Uy", E.neg(
		E.mul(E.cV(), E.div(FVMe.grad(pp, "y"), FVMe.diag("Uy")))))
	reg:correction("p", E.mul("alpha_p", E.prime("p")))

	return reg
end

--
-- POST MORTEM
--

-- General post-mortem ruleset that works for any field list.
-- opts: { velocity_fields, pressure_fields, divU_field }
-- All opts are optional — rules degrade gracefully when fields are absent.
function M.general_post_mortem(opts)
	opts              = opts or {}

	local vel_fields  = opts.velocity_fields or {}
	local pres_fields = opts.pressure_fields or {}
	local divU_field  = opts.divU_field
	local all_fields  = {}

	for _, f in ipairs(vel_fields) do all_fields[#all_fields + 1] = f end
	for _, f in ipairs(pres_fields) do all_fields[#all_fields + 1] = f end

	local function field_history(sage, field, kind, n)
		return sage:cache_query(rules.BY_FIELD_KEY, field .. ":" .. kind,
			{ sort_by = "iter", desc = true, limit = n })
	end

	return rules.post_mortem({

		-- NaN in any field
		rules.pm_rule("nan", function(sage, f, d, diag)
			if not d then return end
			for _, name in ipairs(all_fields) do
				if d.is_nan(name) then
					diag("nan_in_" .. name,
						string.format("%s is NaN at iter %d", name, f.iter))
				end
			end
		end),

		-- divU sanity — only flag NaN, not the value itself (that's a convergence concern)
		rules.pm_rule("divu_nan", function(sage, f, d, diag)
			if not d or not divU_field then return end
			local v = d.max(divU_field)
			if v ~= v then
				diag("divu_nan",
					"divU is NaN from iteration 0 — MWI flux likely uninitialised")
			end
		end),

		-- matrix health for all fields
		rules.pm_rule("matrix_health", function(_, f, d, diag)
			if not d then return end
			for _, name in ipairs(all_fields) do
				local s = d.sys_diag(name)
				if not s then goto continue end
				if not s.all_diagonals_positive then
					diag("negative_diagonal_" .. name,
						string.format("%s: non-positive diagonal — operator sign error or BC issue", name))
				end
				if s.diagonal_dominance < 0 then
					diag("diagonal_not_dominant_" .. name,
						string.format("%s: diagonal dominance = %.3e — matrix likely singular",
							name, s.diagonal_dominance))
				end
				if s.max_asymmetry > 1e-6 then
					diag("asymmetry_" .. name,
						string.format("%s: max asymmetry = %.3e — UDS/TVD correction may be too large",
							name, s.max_asymmetry))
				end
				::continue::
			end
		end),

		-- monotonically growing pressure norm → singular system
		rules.pm_rule("pressure_singular", function(sage, _, _, diag)
			for _, name in ipairs(pres_fields) do
				local h = field_history(sage, name, "field_norm", 999)
				if #h < 3 then goto continue end
				local mono = true
				for i = 2, #h do
					if h[i].value < h[i - 1].value then
						mono = false; break
					end
				end
				if mono then
					diag("pressure_singular_" .. name,
						string.format("%s norm grew monotonically — pin a cell or add a Dirichlet BC", name))
				end
				::continue::
			end
		end),

		-- velocity blowup
		rules.pm_rule("velocity_blowup", function(sage, f, _, diag)
			for _, name in ipairs(vel_fields) do
				local h = field_history(sage, name, "field_norm", 1)
				if h[1] and h[1].value > 1e10 then
					diag("velocity_blowup_" .. name,
						string.format("%s = %.2e at iter %d", name, h[1].value, f.iter))
				end
			end
		end),

		-- stalled residuals across all fields
		rules.pm_rule("stalled_residuals", function(sage, _, _, diag)
			for _, name in ipairs(all_fields) do
				local h = field_history(sage, name, "residual", 5)
				if #h < 5 then goto continue end
				local all_large = true
				for _, e in ipairs(h) do
					if e.value < 0.1 then
						all_large = false; break
					end
				end
				if all_large then
					diag("stalled_residuals_" .. name,
						string.format("%s: residuals > 0.1 for 5 consecutive iters", name))
				end
				::continue::
			end
		end),

		-- residual trajectory — only emit if growing, trajectory printed as part of message
		rules.pm_rule("residual_trajectory", function(sage, _, _, diag)
			for _, name in ipairs(all_fields) do
				local h = field_history(sage, name, "residual", 10)
				if #h < 2 then goto continue end
				local growing = h[1].value > h[#h].value * 10
				if growing then
					local traj = {}
					for i = #h, 1, -1 do
						traj[#traj + 1] = string.format("%.2e", h[i].value)
					end
					diag("residual_growing_" .. name,
						string.format("%s residual grew %.1fx: %s",
							name,
							h[1].value / (h[#h].value + 1e-300),
							table.concat(traj, " -> ")))
				end
				::continue::
			end
		end),

		-- advice
		rules.pm_advice("pressure_singular_p",
			"Pin a cell: add sys:pin_cell(1, 0.0) or a Dirichlet p BC"),
		rules.pm_advice("velocity_blowup_Ux",
			"Reduce relaxation (try alpha_u=0.3) or check BCs"),
		rules.pm_advice("velocity_blowup_Uy",
			"Reduce relaxation (try alpha_u=0.3) or check BCs"),
		rules.pm_advice("stalled_residuals_Ux",
			"Reduce velocity under-relaxation below 0.5"),
		rules.pm_advice("stalled_residuals_Uy",
			"Reduce velocity under-relaxation below 0.5"),
		rules.pm_advice("divu_nan",
			"MWI flux uninitialised — check Rhie-Chow setup"),
	})
end

--
-- SIMPLE
--

local function simple_convergence(opts)
	local pp       = E.prime_name("p")

	opts           = opts or {}
	local res_tol  = opts.tol or 1e-6
	local divu_tol = opts.divu_tol or 1e-9
	local n        = opts.n_consec or 50

	return rules.stopping({
		converged = rules.all_fields({
			Ux   = rules.residual_below(res_tol, n),
			Uy   = rules.residual_below(res_tol, n),
			[pp] = rules.residual_below(res_tol, n),
			divU = rules.field_norm_below(divu_tol, n),
		}),
		diverged = rules.any_field({
			Ux   = rules.any_of(rules.field_above(1e15), rules.field_is_nan()),
			Uy   = rules.any_of(rules.field_above(1e15), rules.field_is_nan()),
			[pp] = rules.any_of(rules.field_above(1e15), rules.field_is_nan()),
			divU = rules.field_is_nan(),
		}),
	})
end

local function simple_progress(every)
	local pp = E.prime_name("p")

	return rules.tabular_progress({
		{ "Ux",   "residual" },
		{ "Uy",   "residual" },
		{ pp,     "residual" },
		{ "divU", "field_norm" },
	}, { every = every })
end

local function simple_post_mortem()
	return M.general_post_mortem({
		velocity_fields = { "Ux", "Uy" },
		pressure_fields = { "p" },
		divU_field      = "divU",
	})
end

function M.SIMPLE(opts)
	opts      = opts or {}
	local pp  = E.prime_name("p")
	local alg = A.new()

	alg:loop(function(a)
		a:solve("U")
		a:monitor("divU")
		a:zero(pp)
		a:solve(pp)
		a:correct("U")
		a:correct("p")
	end, {
		max_iters        = opts.max_iters or 1000,
		linalg_max_iters = opts.linalg_max_iters or 20,
	})

	alg:add_ruleset(simple_convergence(opts))
	alg:add_ruleset(simple_progress(opts.print_every or 25))
	alg:add_ruleset(simple_post_mortem())

	return alg
end

--
-- API
--

M._api = {
	incompressible_registry = "(props?) -> Registry  SIMPLE incompressible NS; props: { rho, mu, alpha_p }",
	stokes_registry         = "(props?) -> Registry  Stokes flow (no convection); props: { mu, alpha_p }",
	general_post_mortem     =
	"(opts?) -> ruleset  field-agnostic post-mortem; opts: { velocity_fields, pressure_fields, divU_field }",
	SIMPLE                  = "(opts?) -> Algorithm  SIMPLE loop; opts: { tol=1e-6, max_iters=1000, print_every=25 }",
}

return M
