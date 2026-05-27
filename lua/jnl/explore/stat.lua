-- jnl/explore/stat.lua - Small statistical helpers
-- <jed@nelson.ac> // 2026-05-27

local M = {}

M._doc = "Small statistical helpers for plain numeric Lua arrays"

--
-- Helpers
--

local function copy_values(xs)
	local ys = {}

	for _, x in ipairs(xs or {}) do
		if type(x) == "number" then
			ys[#ys + 1] = x
		end
	end

	return ys
end

local function sorted_values(xs)
	local ys = copy_values(xs)
	table.sort(ys)
	return ys
end

local function assert_non_empty(xs, name)
	if not xs or #xs == 0 then
		error((name or "stat") .. ": expected at least one numeric value")
	end
end


--
-- Public API
--

function M.count(xs)
	local n = 0

	for _, x in ipairs(xs or {}) do
		if type(x) == "number" then
			n = n + 1
		end
	end

	return n
end

function M.sum(xs)
	local total = 0.0

	for _, x in ipairs(xs or {}) do
		if type(x) == "number" then
			total = total + x
		end
	end

	return total
end

function M.mean(xs)
	local n = M.count(xs)

	if n == 0 then
		return nil
	end

	return M.sum(xs) / n
end

function M.min(xs)
	local best = nil

	for _, x in ipairs(xs or {}) do
		if type(x) == "number" and (best == nil or x < best) then
			best = x
		end
	end

	return best
end

function M.max(xs)
	local best = nil

	for _, x in ipairs(xs or {}) do
		if type(x) == "number" and (best == nil or x > best) then
			best = x
		end
	end

	return best
end

function M.variance(xs, sample)
	local mu = M.mean(xs)

	if mu == nil then
		return nil
	end

	local n = 0
	local ss = 0.0

	for _, x in ipairs(xs or {}) do
		if type(x) == "number" then
			n = n + 1
			ss = ss + (x - mu) * (x - mu)
		end
	end

	if n == 0 then
		return nil
	end

	if sample then
		if n < 2 then
			return nil
		end

		return ss / (n - 1)
	end

	return ss / n
end

function M.std(xs, sample)
	local v = M.variance(xs, sample)

	if v == nil then
		return nil
	end

	return math.sqrt(v)
end

function M.quantile(xs, q)
	if q < 0.0 or q > 1.0 then
		error("quantile: q must be in [0, 1]")
	end

	local ys = sorted_values(xs)
	assert_non_empty(ys, "quantile")

	if #ys == 1 then
		return ys[1]
	end

	local pos = 1.0 + q * (#ys - 1)
	local lo = math.floor(pos)
	local hi = math.ceil(pos)

	if lo == hi then
		return ys[lo]
	end

	local t = pos - lo
	return ys[lo] * (1.0 - t) + ys[hi] * t
end

function M.median(xs)
	return M.quantile(xs, 0.5)
end

function M.quartiles(xs)
	return {
		q1 = M.quantile(xs, 0.25),
		q2 = M.quantile(xs, 0.50),
		q3 = M.quantile(xs, 0.75),
	}
end

function M.summary(xs)
	if M.count(xs) == 0 then
		return {
			n = 0,
		}
	end

	local qs = M.quartiles(xs)

	return {
		n      = M.count(xs),
		mean   = M.mean(xs),
		std    = M.std(xs),
		min    = M.min(xs),
		q1     = qs.q1,
		median = qs.q2,
		q3     = qs.q3,
		max    = M.max(xs),
	}
end

--
-- API
--

M._api = {
	count = {
		args = "xs:table",
		ret  = "number",
		doc  = "Return the number of numeric values in xs.",
	},
	sum = {
		args = "xs:table",
		ret  = "number",
		doc  = "Return the sum of numeric values in xs.",
	},
	mean = {
		args = "xs:table",
		ret  = "number?",
		doc  = "Return the arithmetic mean of numeric values in xs, or nil if empty.",
	},
	min = {
		args = "xs:table",
		ret  = "number?",
		doc  = "Return the minimum numeric value in xs, or nil if empty.",
	},
	max = {
		args = "xs:table",
		ret  = "number?",
		doc  = "Return the maximum numeric value in xs, or nil if empty.",
	},
	variance = {
		args = "xs:table, sample:boolean?",
		ret  = "number?",
		doc  = "Return the variance of numeric values in xs; use sample=true for sample variance.",
	},
	std = {
		args = "xs:table, sample:boolean?",
		ret  = "number?",
		doc  = "Return the standard deviation of numeric values in xs.",
	},
	quantile = {
		args = "xs:table, q:number",
		ret  = "number",
		doc  = "Return the linearly interpolated quantile q for numeric values in xs.",
	},
	median = {
		args = "xs:table",
		ret  = "number",
		doc  = "Return the median of numeric values in xs.",
	},
	quartiles = {
		args = "xs:table",
		ret  = "table",
		doc  = "Return { q1, q2, q3 } for numeric values in xs.",
	},
	summary = {
		args = "xs:table",
		ret  = "table",
		doc  = "Return count, mean, standard deviation, min, quartiles, and max.",
	},
}

return M
