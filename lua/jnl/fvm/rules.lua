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
	["residual_blowup:"]   = "Reduce relaxation",
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
	opts = opts or {}


	local blowup_tol    = opts.blowup_threshold or 1e10
	local stall_window  = opts.stall_window or 5
	local stall_tol     = opts.stall_tol or 0.1
	local traj_window   = opts.trajectory_window or 10
	local growth_factor = opts.growth_factor or 10
	local asym_tol      = opts.asymmetry_tol or 1e-6


	local residual_blowup_tol = opts.residual_blowup_threshold or 1e8


	local rules = {

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

		M.pm_rule("residual_blowup", function(sage, f, _, diag)
			for _, name in ipairs(fields_with(sage, "residual")) do
				local h = latest(sage, name, "residual")
				if h[1] and h[1].value > residual_blowup_tol then
					diag("residual_blowup:" .. name,
						string.format("%s residual = %.2e at iter %d",
							name, h[1].value, f.iter))
				end
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

--
-- API
--

M._doc = "Rule helpers and rulesets for FVM convergence monitoring via Sage."

M._doc_subsection = {
	"Use this module to build convergence, divergence, progress, and post-mortem rules for FVM algorithms.",
	"Field predicates such as residual_below, field_change_below, and field_norm_below return functions of shape pred(field, sage, iter, depth). Pass them directly to alg:converge or alg:guard; do not write predicates expecting a raw residual value.",
	"Use residual_below for solved fields, field_change_below when residuals are noisy, and field_norm_below for monitored derived fields such as divU.",
	"The d argument passed to pm_rule callbacks is sim.diag — the same Diag object documented in jnl.fvm.sim. Use d.field(name), d.max(name), and d.sys_diag(name) to inspect field state at the point of divergence.",
}

M._api = {
	-- predicates: return a pred fn(field, sage, iter, depth) -> bool
	residual_below      = { args = "tol:number, n_consec:int?", ret = "pred", doc = "True if the last n_consec residual facts for the field are all below tol" },
	field_above         = { args = "threshold:number", ret = "pred", doc = "True if the latest field_norm fact exceeds threshold or is NaN" },
	field_is_nan        = { args = "", ret = "pred", doc = "True if the latest field_norm fact is NaN" },
	field_change_below  = { args = "tol:number, n_consec:int?", ret = "pred", doc = "True if the last n_consec field_change facts are all below tol" },
	field_norm_below    = { args = "tol:number, n_consec:int?", ret = "pred", doc = "True if the last n_consec field_norm facts are all below tol; use for MONITOR-tracked fields like divU" },
	field_stagnant      = { args = "tol:number, window:int?", ret = "pred", doc = "True if the field_norm range over window iters is below tol * lo; detects stalled convergence" },
	any_of              = { args = "...:pred", ret = "pred", doc = "True if any supplied predicate returns true" },
	-- criteria: return a criterion fn(sage, iter, depth) -> bool
	all_fields          = { args = "predicates:table<string,pred>", ret = "criterion", doc = "True if every field satisfies its predicate; use for AND convergence" },
	any_field           = { args = "predicates:table<string,pred>", ret = "criterion", doc = "True if any field satisfies its predicate; use for OR divergence guard" },
	-- rulesets
	stopping            = { args = "criteria:table, opts:table?", ret = "ruleset", doc = "Stopping ruleset; criteria: { converged:criterion, diverged:criterion }; opts: { loop_depth=1 }" },
	tabular_progress    = { args = "columns:column[], opts:table?", ret = "ruleset", doc = "Periodic tabular log; opts: { loop_depth=1, every=25, header_every=20 }" },
	post_mortem         = { args = "rules_list:rule[], opts:table?", ret = "ruleset", doc = "Wrap a list of pm_rule entries into a ruleset; opts: { print=true }" },
	general_post_mortem = { args = "opts:table?", ret = "ruleset", doc = "Field-agnostic post-mortem; discovers fields from sage history; opts: { blowup_threshold, stall_window, stall_tol, trajectory_window, growth_factor, asymmetry_tol, residual_blowup_threshold }" },
	-- rule factories
	pm_rule             = { args = "name:string, fn:function", ret = "rule", doc = "Rule that fires on post_mortem facts; fn(sage, fact, diagnostics, diag_fn) should call diag_fn(code, msg) only when significant" },
	pm_advice           = { args = "code:string, msg:string", ret = "rule", doc = "Derive an advice fact when a diagnosis with the given code is seen" },
	pm_print            = { args = "", ret = "rule", doc = "Print all diagnosis and advice facts to stdout" },
}

M._types = {
	pred = {
		doc         = "Field predicate passed to alg:converge or alg:guard",
		constructor = "Rules.residual_below / Rules.field_norm_below / Rules.field_is_nan etc.",
		kind        = "function",
		methods     = {},
	},
	criterion = {
		doc         = "Aggregate criterion over multiple fields; passed to stopping()",
		constructor = "Rules.all_fields / Rules.any_field",
		kind        = "function",
		methods     = {},
	},
	ruleset = {
		doc         = "Table of rules with optional init; passed to sage:add_ruleset or alg:add_ruleset",
		constructor = "Rules.stopping / Rules.tabular_progress / Rules.post_mortem etc.",
		kind        = "table",
		methods     = {},
	},
	rule = {
		doc         = "Single named rule with match and fire functions",
		constructor = "Rules.pm_rule / Rules.pm_advice / Rules.pm_print",
		kind        = "table",
		methods     = {},
	},
	column = {
		doc         = "Two-element array { field, kind } describing one tabular_progress column",
		constructor = "{ 'divU', 'field_norm' } or { 'Ux', 'residual' }",
		kind        = "table",
		methods     = {},
	},
}

return M
