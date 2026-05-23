-- jnl/fvm/rules.lua - rule helpers for sage in an FVM context
-- <jed@nelson.ac> // 2026-05-23

-- deps
local E = require("jnl.core.expr")

local M = {}

--
-- CONVERGENCE
--

-- Cache key used by all residual/norm rules
local BY_FIELD_KEY = "rules:by_field"
M.BY_FIELD_KEY = BY_FIELD_KEY

local function by_field_key_fn(f)
	if f.field and f.kind == "field_norm" then
		return f.field .. ":field_norm"
	end
	if f.field and f.kind == "residual" then
		return f.field .. ":residual"
	end
end

local function ensure_caches(sage)
	sage:ensure_cache(BY_FIELD_KEY, by_field_key_fn)
end

--
-- Predicates (field_name, sage, iter, loop_depth) -> bool
--

function M.residual_below(tol, n_consec)
	n_consec = n_consec or 1
	return function(field, sage, _)
		ensure_caches(sage)
		local h = sage:cache_query(BY_FIELD_KEY, field .. ":residual",
			{ sort_by = "iter", desc = true, limit = n_consec })

		if #h < n_consec then return false end

		for _, f in ipairs(h) do
			if f.value >= tol then return false end
		end
		return true
	end
end

function M.field_above(threshold)
	return function(field, sage, _)
		ensure_caches(sage)

		local h = sage:cache_query(BY_FIELD_KEY, field .. ":field_norm",
			{ sort_by = "iter", desc = true, limit = 1 })

		if #h == 0 then return false end

		return h[1].value > threshold or h[1].value ~= h[1].value
	end
end

function M.field_is_nan()
	return function(field, sage, _)
		ensure_caches(sage)

		local h = sage:cache_query(BY_FIELD_KEY, field .. ":field_norm",
			{ sort_by = "iter", desc = true, limit = 1 })

		if #h == 0 then return false end

		return h[1].value ~= h[1].value
	end
end

function M.field_change_below(tol, n_consec)
	n_consec = n_consec or 1
	return function(field, sage, _)
		ensure_caches(sage)

		local h = sage:cache_query(BY_FIELD_KEY, field .. ":field_norm",
			{ sort_by = "iter", desc = true, limit = n_consec })

		if #h < n_consec then return false end

		for _, f in ipairs(h) do
			if f.norm ~= "normL2_rel_diff" then return false end
			if f.value >= tol then return false end
		end
		return true
	end
end

function M.field_stagnant(tol, window)
	window = window or 10
	return function(field, sage, _)
		ensure_caches(sage)
		local h = sage:cache_query(BY_FIELD_KEY, field .. ":field_norm",
			{ sort_by = "iter", desc = true, limit = window })
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
-- Criteria
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
-- Stopping ruleset
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
			sage:push_action({
				kind = "stop",
				reason = f.kind,
				iter = f.iter,
				loop_depth = f.loop_depth
			})
		end,
	}

	-- add progress tracking optionally
	if opts.progress ~= false then
		local n = opts.progress_n or 10
		rules[#rules + 1] = {
			name  = string.format("progress[depth=%d]", depth),
			match = function(f)
				return f.kind == "field_norm"
					and (f.loop_depth or 1) == depth
					and f.iter % n == 0
			end,
			fire  = function(_, f)
				io.write(string.format("  iter %4d  |%s|  %s = %.3e\n",
					f.iter, E.pretty_sym(f.field), f.norm or "norm", f.value))
			end,
		}
	end

	-- always print convergence/divergence at outer depth
	if depth == 1 then
		rules[#rules + 1] = {
			name  = "print_conclusion",
			match = function(f)
				return (f.kind == "converged" or f.kind == "diverging")
					and f.loop_depth == depth
			end,
			fire  = function(_, f)
				io.write(string.format("%s at iter %d\n", f.kind, f.iter))
			end,
		}
	end

	return { rules = rules }
end

--
-- POST MORTEM
--

-- internal helpers

local function diagnose(sage, f, code, msg)
	sage:derive_once("diagnosis:" .. code .. ":" .. f.iter, {
		kind    = "diagnosis",
		code    = code,
		message = msg,
		iter    = f.iter,
	}, { f.id })
end

--
-- Public rule factories
--

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
		match = function(f)
			return f.kind == "diagnosis" and f.code == code
		end,
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

function M.pm_print()
	return {
		name  = "pm:print",
		match = function(f)
			return f.kind == "diagnosis" or f.kind == "advice"
		end,
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

return M
