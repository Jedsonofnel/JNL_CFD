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
-- API
--

M._doc = "Rule helpers and rulesets for FVM convergence monitoring via Sage."

M._api = {
	-- predicates
	residual_below     = "(tol, n_consec?) -> pred  true if last n residuals all < tol",
	field_above        = "(threshold) -> pred  true if latest field_norm > threshold or NaN",
	field_is_nan       = "() -> pred  true if latest field_norm is NaN",
	field_change_below = "(tol, n_consec?) -> pred  true if last n normL2_rel_diff < tol",
	field_stagnant     = "(tol, window?) -> pred  true if field_norm range < tol*lo over window iters",
	field_norm_below   = "(tol, n_consec?) -> pred  true if last n field_norm values all < tol",
	any_of             = "(...preds) -> pred  true if any child predicate is true",
	-- criteria
	all_fields         = "(predicates:{field->pred}) -> criterion  true if all fields satisfy pred",
	any_field          = "(predicates:{field->pred}) -> criterion  true if any field satisfies pred",
	-- rulesets
	stopping           = "(criteria, opts?) -> ruleset  convergence/divergence stopping rules",
	tabular_progress   = "(columns:{{field,kind}}, opts?) -> ruleset  periodic tabular log",
	post_mortem        = "(rules_list, opts?) -> ruleset  post-mortem diagnosis ruleset",
	-- rule factories
	pm_rule            = "(name, fn) -> rule  fire fn on post_mortem fact; fn calls diag() only when significant",
	pm_advice          = "(code, msg) -> rule  derive advice fact when diagnosis code seen",
	pm_print           = "() -> rule  print all diagnosis and advice facts",
}

M._types = {
	pred      = "(field:string, sage, iter, depth) -> bool",
	criterion = "(sage, iter, depth) -> bool",
	ruleset   = "{ rules:{rule}, init:fn? }  — passed to sage:add_ruleset or alg:add_ruleset",
	rule      = "{ name:string, match:fn, fire:fn }",
	column    = "{ [1]:field:string, [2]:kind:'residual'|'field_norm' }",
}

return M
