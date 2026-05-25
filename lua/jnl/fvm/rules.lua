-- jnl/fvm/rules.lua - rule helpers for sage in an FVM context
-- <jed@nelson.ac> // 2026-05-23

local E = require("jnl.core.expr")

local M = {}

--
-- CACHE
--

-- Single cache key for all residual/norm facts keyed by field+kind
local BY_FIELD_KEY = "rules:by_field"
M.BY_FIELD_KEY = BY_FIELD_KEY

local function by_field_key_fn(f)
	if not f.field then return nil end
	if f.kind == "field_norm"
		or f.kind == "field_change"
		or f.kind == "residual" then
		return f.field .. ":" .. f.kind
	end
end

local function ensure_cache(sage)
	sage:ensure_cache(BY_FIELD_KEY, by_field_key_fn)
end

local function latest(sage, field, kind, n)
	return sage:cache_query(BY_FIELD_KEY, field .. ":" .. kind,
		{ sort_by = "iter", desc = true, limit = n or 1 })
end

--
-- PREDICATES  (field:string, sage, iter, loop_depth) -> bool
--

function M.residual_below(tol, n_consec)
	n_consec = n_consec or 1
	return function(field, sage)
		ensure_cache(sage)
		local h = latest(sage, field, "residual", n_consec)
		if #h < n_consec then return false end
		for _, f in ipairs(h) do
			if f.value >= tol then return false end
		end
		return true
	end
end

function M.field_above(threshold)
	return function(field, sage)
		ensure_cache(sage)
		local h = latest(sage, field, "field_norm")
		if #h == 0 then return false end
		return h[1].value > threshold or h[1].value ~= h[1].value
	end
end

function M.field_is_nan()
	return function(field, sage)
		ensure_cache(sage)
		local h = latest(sage, field, "field_norm")
		if #h == 0 then return false end
		return h[1].value ~= h[1].value
	end
end

function M.field_change_below(tol, n_consec)
	n_consec = n_consec or 1
	return function(field, sage)
		ensure_cache(sage)
		local h = latest(sage, field, "field_change", n_consec)
		if #h < n_consec then return false end
		for _, f in ipairs(h) do
			if f.value >= tol then return false end
		end
		return true
	end
end

function M.field_norm_below(tol, n_consec)
	n_consec = n_consec or 1

	return function(field, sage)
		ensure_cache(sage)

		local h = latest(sage, field, "field_norm", n_consec)
		if #h < n_consec then return false end

		for _, f in ipairs(h) do
			if f.value >= tol then return false end
		end

		return true
	end
end

function M.field_stagnant(tol, window)
	window = window or 10
	return function(field, sage)
		ensure_cache(sage)
		local h = latest(sage, field, "field_change", window)
		if #h < window then return false end
		local hi, lo = h[1].value, h[1].value
		for _, e in ipairs(h) do
			hi = math.max(hi, e.value)
			lo = math.min(lo, e.value)
		end
		return (hi - lo) < tol * (lo + 1e-300)
	end
end

function M.any_of(...)
	local preds = { ... }
	return function(field, sage, iter, depth)
		for _, p in ipairs(preds) do
			if p(field, sage, iter, depth) then return true end
		end
		return false
	end
end

--
-- CRITERIA  (sage, iter, loop_depth) -> bool
--

function M.all_fields(predicates)
	return function(sage, iter, depth)
		for field, pred in pairs(predicates) do
			if not pred(field, sage, iter, depth) then return false end
		end
		return true
	end
end

function M.any_field(predicates)
	return function(sage, iter, depth)
		for field, pred in pairs(predicates) do
			if pred(field, sage, iter, depth) then return true end
		end
		return false
	end
end

--
-- STOPPING RULESET
--

function M.stopping(criteria, opts)
	opts        = opts or {}
	local depth = opts.loop_depth or 1
	local conv  = criteria.converged
	local div   = criteria.diverged
	local rules = {}

	if conv then
		rules[#rules + 1] = {
			name  = string.format("convergence_check[depth=%d]", depth),
			match = function(f) return f.kind == "iter_end" and f.loop_depth == depth end,
			fire  = function(sage, f)
				if conv(sage, f.iter, f.loop_depth) then
					sage:derive({ kind = "converged", iter = f.iter, loop_depth = depth }, { f.id })
				end
			end,
		}
	end

	if div then
		rules[#rules + 1] = {
			name  = string.format("divergence_check[depth=%d]", depth),
			match = function(f) return f.kind == "iter_end" and f.loop_depth == depth end,
			fire  = function(sage, f)
				if div(sage, f.iter, f.loop_depth) then
					sage:derive({ kind = "diverging", iter = f.iter, loop_depth = depth }, { f.id })
				end
			end,
		}
	end

	rules[#rules + 1] = {
		name  = string.format("act_on_conclusion[depth=%d]", depth),
		match = function(f)
			return (f.kind == "converged" or f.kind == "diverging")
				and f.loop_depth == depth
		end,
		fire  = function(sage, f)
			sage:push_action({ kind = "stop", reason = f.kind, iter = f.iter, loop_depth = f.loop_depth })
		end,
	}

	if depth == 1 then
		rules[#rules + 1] = {
			name  = "print_conclusion",
			match = function(f)
				return (f.kind == "converged" or f.kind == "diverging") and f.loop_depth == depth
			end,
			fire  = function(_, f)
				io.write(string.format("%s at iter %d\n", f.kind, f.iter))
			end,
		}
	end

	return { rules = rules }
end

--
-- TABULAR PROGRESS
--

function M.tabular_progress(columns, opts)
	opts = opts or {}


	local depth     = opts.loop_depth or 1
	local every     = opts.every or 25
	local hdr_every = opts.header_every or 20

	local function header()
		local cols = { string.format("%6s", "iter") }
		for _, col in ipairs(columns) do
			cols[#cols + 1] = string.format("%12s", E.pretty_sym(col[1]))
		end
		io.write(table.concat(cols, "  ") .. "\n")
	end

	local function fmt(v)
		if v ~= v then return string.format("%12s", "nan") end
		return string.format("%12.4e", v)
	end

	local print_count = 0
	local started = false

	local function is_iter_end(f)
		return f.kind == "iter_end" and f.loop_depth == depth
	end

	local rules = {
		{
			name  = string.format("tabular_header[depth=%d]", depth),
			match = is_iter_end,
			fire  = function()
				if started then return end
				header()
				started = true
				print_count = 0
			end,
		},
		{
			name  = string.format("tabular_row[depth=%d]", depth),
			match = function(f) return is_iter_end(f) and f.iter % every == 0 end,
			fire  = function(sage, f)
				if print_count > 0 and print_count % hdr_every == 0 then header() end
				print_count = print_count + 1

				local cols = { string.format("%6d", f.iter) }
				for _, col in ipairs(columns) do
					local h = latest(sage, col[1], col[2])
					cols[#cols + 1] = fmt(h[1] and h[1].value or math.huge)
				end
				io.write(table.concat(cols, "  ") .. "\n")
			end,
		},
		{
			name  = "tabular_conclusion",
			match = function(f)
				return (f.kind == "converged" or f.kind == "diverging")
					and f.loop_depth == depth
			end,
			fire  = function(sage, f)
				-- always print the final row at the conclusion iter
				local cols = { string.format("%6d", f.iter) }
				for _, col in ipairs(columns) do
					local h = latest(sage, col[1], col[2])
					cols[#cols + 1] = fmt(h[1] and h[1].value or math.huge)
				end
				io.write(table.concat(cols, "  ") .. "\n")
			end,
		},
	}

	return {
		rules = rules,
		init  = function(sage) sage:ensure_cache(BY_FIELD_KEY, by_field_key_fn) end,
	}
end

--
-- POST MORTEM
--

local function diagnose(sage, f, code, msg)
	sage:derive_once("diagnosis:" .. code .. ":" .. f.iter, {
		kind    = "diagnosis",
		code    = code,
		message = msg,
		iter    = f.iter,
	}, { f.id })
end

-- fn(sage, fact, diagnostics, diag_fn) — call diag_fn(code, msg) only when something is wrong
function M.pm_rule(name, fn)
	return {
		name  = "pm:" .. name,
		match = function(f) return f.kind == "post_mortem" end,
		fire  = function(sage, f)
			fn(sage, f, f.diagnostics, function(code, msg)
				diagnose(sage, f, code, msg)
			end)
		end,
	}
end

function M.pm_advice(code, msg)
	return {
		name  = "advice:" .. code,
		match = function(f) return f.kind == "diagnosis" and f.code == code end,
		fire  = function(sage, f)
			sage:derive_once("advice:" .. code, {
				kind     = "advice",
				for_code = code,
				message  = msg,
				iter     = f.iter,
			}, { f.id })
		end,
	}
end

-- prints only diagnosis and advice facts — informational dumps belong in pm_rule fns
-- and should go through diag() so they only appear when significant
function M.pm_print()
	return {
		name  = "pm:print",
		match = function(f) return f.kind == "diagnosis" or f.kind == "advice" end,
		fire  = function(_, f)
			local tag = f.kind == "advice" and "  hint" or "  diag"
			io.write(string.format("[POST-MORTEM] %s: %s\n", tag, f.message))
		end,
	}
end

function M.post_mortem(rules_list, opts)
	opts = opts or {}
	local rules = {}
	for _, r in ipairs(rules_list) do
		rules[#rules + 1] = r
	end
	if opts.print ~= false then
		rules[#rules + 1] = M.pm_print()
	end
	return { rules = rules }
end

--
-- GENERAL POST MORTEM
--

-- Discover all field names that have produced facts of a given kind.
-- Called once at post-mortem time so O(n) over facts is fine.
local function fields_with(sage, kind)
	local seen, out = {}, {}
	for _, f in ipairs(sage:query({ kind = kind })) do
		if f.field and not seen[f.field] then
			seen[f.field] = true
			out[#out + 1] = f.field
		end
	end
	return out
end

-- Prefix-keyed advice table — matched against diagnosis codes dynamically.
local ADVICE = {
	["nan:"]               = "Check BCs and initial conditions; reduce relaxation or dt",
	["blowup:"]            = "Reduce under-relaxation or dt; verify BC magnitudes",
	["monotone_growth:"]   = "Pin a reference cell or add a Dirichlet BC to fix the level",
	["stalled:"]           = "Reduce under-relaxation; inspect mesh quality and skewness",
	["residual_growing:"]  = "Reduce under-relaxation or dt; check for oscillating BCs",
	["neg_diagonal:"]      = "Check operator sign conventions and BC types",
	["not_diag_dominant:"] = "Reduce convection or increase diffusion; check CFL",
	["asymmetry:"]         = "Reduce TVD correction strength or switch to UDS temporarily",
}

local function prefix_advice(sage, f)
	for prefix, msg in pairs(ADVICE) do
		if f.code:sub(1, #prefix) == prefix then
			sage:derive_once("advice:" .. f.code, {
				kind     = "advice",
				for_code = f.code,
				message  = msg,
				iter     = f.iter,
			}, { f.id })
			return
		end
	end
end

function M.general_post_mortem(opts)
	opts                = opts or {}

	local blowup_tol    = opts.blowup_threshold or 1e10
	local stall_window  = opts.stall_window or 5
	local stall_tol     = opts.stall_tol or 0.1
	local traj_window   = opts.trajectory_window or 10
	local growth_factor = opts.growth_factor or 10
	local asym_tol      = opts.asymmetry_tol or 1e-6

	local rules         = {

		-- NaN in any monitored field
		M.pm_rule("nan", function(sage, f, _, diag)
			for _, name in ipairs(fields_with(sage, "field_norm")) do
				local h = latest(sage, name, "field_norm")
				if h[1] and h[1].value ~= h[1].value then
					diag("nan:" .. name,
						string.format("%s is NaN at iter %d", name, f.iter))
				end
			end
		end),

		-- Norm above blowup threshold
		M.pm_rule("blowup", function(sage, f, _, diag)
			for _, name in ipairs(fields_with(sage, "field_norm")) do
				local h = latest(sage, name, "field_norm")
				if h[1] and h[1].value > blowup_tol then
					diag("blowup:" .. name,
						string.format("%s norm = %.2e at iter %d", name, h[1].value, f.iter))
				end
			end
		end),

		-- Monotonically growing norm -> likely singular system.
		-- h is sorted desc by iter: h[1] most recent, h[#h] oldest.
		-- Growth means h[i-1].value > h[i].value (more recent > older).
		M.pm_rule("monotone_growth", function(sage, _, _, diag)
			for _, name in ipairs(fields_with(sage, "field_norm")) do
				local h = latest(sage, name, "field_norm", 999)
				if #h < 3 then goto continue end
				local growing = true
				for i = 2, #h do
					if h[i - 1].value <= h[i].value then
						growing = false; break
					end
				end
				if growing then
					diag("monotone_growth:" .. name,
						string.format("%s norm grew monotonically over %d iters — possible singular system",
							name, #h))
				end
				::continue::
			end
		end),

		-- Residuals stuck high for stall_window consecutive iters
		M.pm_rule("stalled_residuals", function(sage, _, _, diag)
			for _, name in ipairs(fields_with(sage, "residual")) do
				local h = latest(sage, name, "residual", stall_window)
				if #h < stall_window then goto continue end
				local stalled = true
				for _, e in ipairs(h) do
					if e.value < stall_tol then
						stalled = false; break
					end
				end
				if stalled then
					diag("stalled:" .. name,
						string.format("%s: residuals > %.2e for %d consecutive iters",
							name, stall_tol, stall_window))
				end
				::continue::
			end
		end),

		-- Residual growing faster than growth_factor over traj_window iters
		M.pm_rule("residual_trajectory", function(sage, _, _, diag)
			for _, name in ipairs(fields_with(sage, "residual")) do
				local h = latest(sage, name, "residual", traj_window)
				if #h < 2 then goto continue end
				-- h[1] most recent, h[#h] oldest; growing if recent >> oldest
				if h[1].value > h[#h].value * growth_factor then
					local traj = {}
					for i = #h, 1, -1 do
						traj[#traj + 1] = string.format("%.2e", h[i].value)
					end
					diag("residual_growing:" .. name,
						string.format("%s residual grew %.1fx: %s",
							name,
							h[1].value / (h[#h].value + 1e-300),
							table.concat(traj, " -> ")))
				end
				::continue::
			end
		end),

		-- Matrix health via diagnostics object — optional, degrades gracefully
		M.pm_rule("matrix_health", function(sage, _, d, diag)
			if not (d and d.sys_diag) then return end
			for _, name in ipairs(fields_with(sage, "field_norm")) do
				local s = d.sys_diag(name)
				if not s then goto continue end
				if not s.all_diagonals_positive then
					diag("neg_diagonal:" .. name,
						string.format("%s: non-positive diagonal — check operator signs and BCs", name))
				end
				if s.diagonal_dominance < 0 then
					diag("not_diag_dominant:" .. name,
						string.format("%s: diagonal dominance = %.3e — matrix may be singular",
							name, s.diagonal_dominance))
				end
				if s.max_asymmetry > asym_tol then
					diag("asymmetry:" .. name,
						string.format("%s: max asymmetry = %.3e — TVD/UDS correction may be too large",
							name, s.max_asymmetry))
				end
				::continue::
			end
		end),

		-- Emit advice for any diagnosis fact whose code matches a known prefix
		{
			name  = "pm:advice",
			match = function(f) return f.kind == "diagnosis" end,
			fire  = function(sage, f) prefix_advice(sage, f) end,
		},
	}

	return {
		rules = rules,
		init  = function(sage) sage:ensure_cache(BY_FIELD_KEY, by_field_key_fn) end,
	}
end

--
-- API
--

M._doc = "Rule helpers and rulesets for FVM convergence monitoring via Sage."

M._doc_subsection = "The d argument passed to pm_rule callbacks is sim.diag — the same Diag object " ..
	"documented in jnl.fvm.sim. Use d.field(name), d.max(name), and d.sys_diag(name) " ..
	"to inspect field state at the point of divergence."


M._api = {
	-- predicates
	residual_below      = "(tol, n_consec?) -> pred  true if last n residuals all < tol",
	field_above         = "(threshold) -> pred  true if latest field_norm > threshold or NaN",
	field_is_nan        = "() -> pred  true if latest field_norm is NaN",
	field_change_below  = "(tol, n_consec?) -> pred  true if last n normL2_rel_diff < tol",
	field_stagnant      = "(tol, window?) -> pred  true if field_norm range < tol*lo over window iters",
	field_norm_below    = "(tol, n_consec?) -> pred  true if last n field_norm values all < tol",
	any_of              = "(...preds) -> pred  true if any child predicate is true",
	-- criteria
	all_fields          = "(predicates:{field->pred}) -> criterion  true if all fields satisfy pred",
	any_field           = "(predicates:{field->pred}) -> criterion  true if any field satisfies pred",
	-- rulesets
	stopping            = "(criteria, opts?) -> ruleset  convergence/divergence stopping rules",
	tabular_progress    = "(columns:{{field,kind}}, opts?) -> ruleset  periodic tabular log",
	post_mortem         = "(rules_list, opts?) -> ruleset  post-mortem diagnosis ruleset",
	-- rule factories
	pm_rule             = "(name, fn) -> rule  fire fn on post_mortem fact; fn calls diag() only when significant",
	pm_advice           = "(code, msg) -> rule  derive advice fact when diagnosis code seen",
	pm_print            = "() -> rule  print all diagnosis and advice facts",
	general_post_mortem =
	"(opts?) -> ruleset  field-agnostic post-mortem; discovers fields from sage history. opts: { blowup_threshold, stall_window, stall_tol, trajectory_window, growth_factor, asymmetry_tol }",
}

M._types = {
	pred      = "(field:string, sage, iter, depth) -> bool",
	criterion = "(sage, iter, depth) -> bool",
	ruleset   = "{ rules:{rule}, init:fn? }  — passed to sage:add_ruleset or alg:add_ruleset",
	rule      = "{ name:string, match:fn, fire:fn }",
	column    = "{ [1]:field:string, [2]:kind:'residual'|'field_norm' }",
}

return M
