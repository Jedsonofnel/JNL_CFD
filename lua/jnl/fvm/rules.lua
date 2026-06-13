-- jnl/fvm/rules.lua - Convergence and divergence stopping rules for FVM cases.
-- <jed@nelson.ac> // 2026-06-10

--- Convergence and divergence criterion constructors for FVM cases.
---
--- Criterion objects are plain tables passed to Algorithm:converge() and
--- Algorithm:guard() before the Case is constructed:
---
---     alg:converge(Rules.residual_below("*", 1e-4))
---     alg:guard(Rules.nan_guard())
---     alg:guard(Rules.norm_above("p", 1e8))
---
--- The wildcard field `"*"` expands at runtime to every field that has
--- produced residual telemetry, so `residual_below("*", tol)` is the
--- standard all-fields convergence criterion.
local M            = {}

--- Convergence criterion spec accepted by Algorithm:converge().
---@class ConvCrit
---@field kind "conv_crit"
---@field field string   Field name or "*" to match all telemetry fields.
---@field op string      "residual_below" | "change_below"
---@field threshold number
---@field n_consec integer Consecutive iterations the criterion must hold.

--- Divergence guard spec accepted by Algorithm:guard().
---@class DivCrit
---@field kind "div_crit"
---@field field string   Field name or "*" to match all telemetry fields.
---@field op string      "residual_above" | "norm_above" | "nan"
---@field threshold number?

--
-- Telemetry cache
--

-- Sage cache key used to index field telemetry by field name and kind.
---@private
local BY_FIELD_KEY = "rules:by_field"
M.BY_FIELD_KEY     = BY_FIELD_KEY

local function by_field_key_fn(f)
	if not f.field then return nil end
	if f.kind == "residual"
		or f.kind == "field_change"
		or f.kind == "field_norm" then
		return f.field .. ":" .. f.kind
	end
end

local function ensure_cache(sage)
	sage:ensure_cache(BY_FIELD_KEY, by_field_key_fn)
end

local function latest_n(sage, field, kind, n)
	return sage:cache_query(BY_FIELD_KEY, field .. ":" .. kind,
		{ sort_by = "iter", desc = true, limit = n or 1 })
end

--
-- Criterion constructors
--

--- Convergence criterion: field residual below threshold for n_consec consecutive iterations.
---
--- Pass `"*"` as the field to require all fields with residual telemetry to converge.
---@param field string     Field name or "*".
---@param threshold number Residual threshold.
---@param n_consec? integer Consecutive iterations required; defaults to 1.
---@return ConvCrit
function M.residual_below(field, threshold, n_consec)
	assert(type(field) == "string", "residual_below: field must be a string")
	assert(type(threshold) == "number", "residual_below: threshold must be a number")
	return {
		kind      = "conv_crit",
		field     = field,
		op        = "residual_below",
		threshold = threshold,
		n_consec  = n_consec or 1,
	}
end

--- Convergence criterion: field L2 change below threshold for n_consec consecutive iterations.
---@param field string     Field name or "*".
---@param threshold number Change threshold.
---@param n_consec? integer Consecutive iterations required; defaults to 1.
---@return ConvCrit
function M.change_below(field, threshold, n_consec)
	assert(type(field) == "string", "change_below: field must be a string")
	assert(type(threshold) == "number", "change_below: threshold must be a number")
	return {
		kind      = "conv_crit",
		field     = field,
		op        = "change_below",
		threshold = threshold,
		n_consec  = n_consec or 1,
	}
end

--- Divergence guard: stop when field residual exceeds threshold.
---@param field string     Field name or "*".
---@param threshold? number Residual limit; defaults to 1e10.
---@return DivCrit
function M.residual_above(field, threshold)
	assert(type(field) == "string", "residual_above: field must be a string")
	return {
		kind      = "div_crit",
		field     = field,
		op        = "residual_above",
		threshold = threshold or 1e10,
	}
end

--- Divergence guard: stop when field L2 norm exceeds threshold.
---
--- Also fires on NaN, so this catches both blowup and breakdown before the
--- residual has a chance to diverge.
---@param field string     Field name or "*".
---@param threshold? number Norm limit; defaults to 1e10.
---@return DivCrit
function M.norm_above(field, threshold)
	assert(type(field) == "string", "norm_above: field must be a string")
	return {
		kind      = "div_crit",
		field     = field,
		op        = "norm_above",
		threshold = threshold or 1e10,
	}
end

--- Divergence guard: stop when a NaN is detected in a field.
---@param field? string Field name or "*"; defaults to "*" (any field).
---@return DivCrit
function M.nan_guard(field)
	return {
		kind  = "div_crit",
		field = field or "*",
		op    = "nan",
	}
end

--
-- Metric evaluators
--

local eval_conv          = {}
local eval_div           = {}

eval_conv.residual_below = function(sage, field, crit)
	local h = latest_n(sage, field, "residual", crit.n_consec)
	if #h < crit.n_consec then return false end
	for _, f in ipairs(h) do
		if f.value >= crit.threshold then return false end
	end
	return true
end

eval_conv.change_below   = function(sage, field, crit)
	local h = latest_n(sage, field, "field_change", crit.n_consec)
	if #h < crit.n_consec then return false end
	for _, f in ipairs(h) do
		if f.value >= crit.threshold then return false end
	end
	return true
end

eval_div.nan             = function(sage, field, _)
	local h = latest_n(sage, field, "field_norm", 1)
	if #h == 0 then return false end
	local v = h[1].value
	return v ~= v
end

eval_div.residual_above  = function(sage, field, crit)
	local h = latest_n(sage, field, "residual", 1)
	if #h == 0 then return false end
	return h[1].value > crit.threshold
end

eval_div.norm_above      = function(sage, field, crit)
	local h = latest_n(sage, field, "field_norm", 1)
	if #h == 0 then return false end
	local v = h[1].value
	return v ~= v or v > crit.threshold
end

--
-- Criteria helpers
--

local function active_criteria(sage, kind)
	local all    = sage:query({ kind = kind })
	local latest = {}
	for _, c in ipairs(all) do
		local key = c.field .. ":" .. (c.op or "")
		if not latest[key] or c.id > latest[key].id then
			latest[key] = c
		end
	end
	local out = {}
	for _, c in pairs(latest) do out[#out + 1] = c end
	return out
end

local function fields_with_telemetry(sage)
	local seen, out = {}, {}
	for _, f in ipairs(sage:query({ kind = "residual" })) do
		if f.field and not seen[f.field] then
			seen[f.field] = true
			out[#out + 1] = f.field
		end
	end
	return out
end

local function expand_criteria(crits, sage)
	local all_fields = nil
	local out = {}
	for _, c in ipairs(crits) do
		if c.field == "*" then
			all_fields = all_fields or fields_with_telemetry(sage)
			for _, fname in ipairs(all_fields) do
				local copy = {}
				for k, v in pairs(c) do copy[k] = v end
				copy.field = fname
				out[#out + 1] = copy
			end
		else
			out[#out + 1] = c
		end
	end
	return out
end

--
-- Stopping ruleset
--

--- Return the standard FVM stopping ruleset.
---
--- Registers convergence and divergence checking rules with a Sage instance.
--- Case adds this ruleset automatically; call it explicitly only when
--- constructing a Sage outside a Case.
---@return table ruleset
function M.stopping_ruleset()
	return {
		init = function(sage)
			ensure_cache(sage)
		end,

		rules = {

			-- ALL active conv_crit must be satisfied for the solver to converge.
			{
				name  = "convergence_check",
				kinds = { iter_end = true },
				match = function(f) return f.kind == "iter_end" end,
				fire  = function(sage, f)
					local crits = active_criteria(sage, "conv_crit")
					if #crits == 0 then return end

					local expanded = expand_criteria(crits, sage)
					if #expanded == 0 then return end

					for _, c in ipairs(expanded) do
						local fn = eval_conv[c.op]
						if not fn then
							io.stderr:write(
								"rules: unknown conv op '" .. tostring(c.op) .. "'\n")
							return
						end
						if not fn(sage, c.field, c) then return end
					end

					sage:derive({
						kind       = "converged",
						iter       = f.iter,
						loop_depth = f.loop_depth or 1,
					}, { f.id })
				end,
			},

			-- ANY active div_crit being satisfied stops the run immediately.
			{
				name  = "divergence_check",
				kinds = { iter_end = true },
				match = function(f) return f.kind == "iter_end" end,
				fire  = function(sage, f)
					local crits = active_criteria(sage, "div_crit")
					if #crits == 0 then return end

					local expanded = expand_criteria(crits, sage)

					for _, c in ipairs(expanded) do
						local fn = eval_div[c.op]
						if not fn then
							io.stderr:write(
								"rules: unknown div op '" .. tostring(c.op) .. "'\n")
							goto continue
						end

						if fn(sage, c.field, c) then
							sage:derive({
								kind       = "diverging",
								iter       = f.iter,
								field      = c.field,
								op         = c.op,
								loop_depth = f.loop_depth or 1,
							}, { f.id })
							return
						end

						::continue::
					end
				end,
			},

			-- Push a stop action to Case on any convergence or divergence conclusion.
			{
				name  = "stop_on_conclusion",
				kinds = { converged = true, diverging = true },
				match = function(f)
					return f.kind == "converged" or f.kind == "diverging"
				end,
				fire  = function(sage, f)
					sage:push_action({
						kind   = "stop",
						reason = f.kind,
						iter   = f.iter,
						field  = f.field,
						op     = f.op,
					})
				end,
			},
		},
	}
end

--
-- Case integration helpers
--

--- Post all convergence and divergence criteria from an algorithm as Sage facts.
---
--- Called automatically by Case:reset(). Invoke directly only when managing
--- a Sage instance outside a Case.
---@param sage table Sage instance.
---@param alg Algorithm Algorithm carrying convergence and divergence criterion lists.
function M.assert_alg_criteria(sage, alg)
	for _, spec in ipairs(alg.convergence or {}) do
		sage:assert(spec)
	end
	for _, spec in ipairs(alg.divergence or {}) do
		sage:assert(spec)
	end
end

return M
