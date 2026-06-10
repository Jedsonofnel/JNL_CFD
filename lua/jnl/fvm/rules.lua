-- jnl/fvm/rules.lua
-- Convergence/divergence stopping rules for FVM Case.

local M            = {}

--
-- Telemetry cache
--

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
-- Criterion fact constructors
--

-- Convergence: field residual below threshold for n_consec consecutive iters.
-- field = "*" means all fields that have produced residual facts.
---@param field    string    field name or "*"
---@param threshold number
---@param n_consec integer?  default 1
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

-- Convergence: field L2 change below threshold for n_consec iters.
---@param field     string
---@param threshold number
---@param n_consec  integer?
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

-- Divergence: field residual exceeds threshold.
---@param field     string
---@param threshold number   default 1e10
function M.residual_above(field, threshold)
	assert(type(field) == "string", "residual_above: field must be a string")
	return {
		kind      = "div_crit",
		field     = field,
		op        = "residual_above",
		threshold = threshold or 1e10,
	}
end

-- Divergence: field norm exceeds threshold (catches blowup before residual diverges).
---@param field     string
---@param threshold number   default 1e10
function M.norm_above(field, threshold)
	assert(type(field) == "string", "norm_above: field must be a string")
	return {
		kind      = "div_crit",
		field     = field,
		op        = "norm_above",
		threshold = threshold or 1e10,
	}
end

-- Divergence: NaN in field. field="*" checks all fields with telemetry.
---@param field string?   default "*"
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

local eval_conv = {}
local eval_div = {}

eval_conv.residual_below = function(sage, field, crit)
	local h = latest_n(sage, field, "residual", crit.n_consec)
	if #h < crit.n_consec then return false end
	for _, f in ipairs(h) do
		if f.value >= crit.threshold then return false end
	end
	return true
end

eval_conv.change_below = function(sage, field, crit)
	local h = latest_n(sage, field, "field_change", crit.n_consec)
	if #h < crit.n_consec then return false end
	for _, f in ipairs(h) do
		if f.value >= crit.threshold then return false end
	end
	return true
end

eval_div.nan = function(sage, field, _)
	local h = latest_n(sage, field, "field_norm", 1)
	if #h == 0 then return false end
	local v = h[1].value
	return v ~= v -- NaN check
end

eval_div.residual_above = function(sage, field, crit)
	local h = latest_n(sage, field, "residual", 1)
	if #h == 0 then return false end
	return h[1].value > crit.threshold
end

eval_div.norm_above = function(sage, field, crit)
	local h = latest_n(sage, field, "field_norm", 1)
	if #h == 0 then return false end
	local v = h[1].value
	return v ~= v or v > crit.threshold -- NaN also trips this
end

--
-- Criteria helpers
--

-- Returns the active (latest-by-id) criterion for each (field, op) pair.
-- Posting a new conv_crit for the same (field, op) mid-solve supersedes
-- the old one because it has a higher fact id.
local function active_criteria(sage, kind)
	local all    = sage:query({ kind = kind })
	local latest = {} -- key = field..":"..op -> criterion fact
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

-- Returns all distinct field names that have produced residual facts.
-- Used to expand wildcard criteria.
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

-- Expands wildcard field="*" into one criterion per known telemetry field.
local function expand_criteria(crits, sage)
	local all_fields = nil -- lazy: only computed if a wildcard exists
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

function M.stopping_ruleset()
	return {
		init = function(sage)
			ensure_cache(sage)
		end,

		rules = {

			-- Convergence: ALL active conv_crit must be satisfied.
			-- Fires on iter_end; if all criteria pass, derives "converged".
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

			-- Divergence: ANY active div_crit being satisfied stops the run.
			-- Reports which field and op triggered the stop.
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
							return -- first divergence wins; no point continuing
						end

						::continue::
					end
				end,
			},

			-- Act on any conclusion by pushing a stop action to Case.
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
						field  = f.field, -- set on diverging, nil on converged
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

-- Posts all convergence and divergence criteria from alg as facts.
-- alg.convergence and alg.divergence are flat lists of criterion specs
-- (plain tables produced by the constructors above, stored by alg:converge
-- and alg:guard).
function M.assert_alg_criteria(sage, alg)
	for _, spec in ipairs(alg.convergence or {}) do
		sage:assert(spec)
	end
	for _, spec in ipairs(alg.divergence or {}) do
		sage:assert(spec)
	end
end

return M
