-- jnl/sage.lua - simple rule engine (JTMS lite for now)
-- <jed@nelson.ac> // 2026-05-23

local Sage = {}
Sage.__index = Sage

function Sage.new()
	return setmetatable({
		facts = {}, -- all facts
		rules = {}, -- list of { name, match, fire }
		actions = {}, -- pending actions
		_caches = {}, -- name -> { facts, key_fn } for indexed lookup
	}, Sage)
end

--
-- Facts
--

function Sage:assert(fact)
	fact.id = #self.facts + 1
	fact.derived = false
	self.facts[#self.facts + 1] = fact
	self:_update_caches(fact)
	self:_propagate(fact)
end

function Sage:derive(fact, support_ids)
	fact.id = #self.facts + 1
	fact.derived = true
	fact.supports = type(support_ids) == "table" and support_ids or { support_ids }
	self.facts[#self.facts + 1] = fact
	self:_update_caches(fact)
	self:_propagate(fact)
end

function Sage:derive_once(key, fact, support_ids)
	if self._derived_keys and self._derived_keys[key] then return false end
	self._derived_keys = self._derived_keys or {}
	self._derived_keys[key] = true
	self:derive(fact, support_ids)
	return true
end

function Sage:_propagate(fact)
	self._queue = self._queue or {}
	self._queue[#self._queue + 1] = fact
	if self._draining then return end
	self._draining = true

	while #self._queue > 0 do
		local f = table.remove(self._queue, 1)
		for _, rule in ipairs(self.rules) do
			if (not rule.kinds or rule.kinds[f.kind]) and rule.match(f) then
				rule.fire(self, f)
			end
		end
	end
	self._draining = false
end

--
-- Actions (consumed by orchestrator)
--

function Sage:push_action(action)
	self.actions[#self.actions + 1] = action
end

function Sage:pop_actions()
	local a = self.actions
	self.actions = {}
	return a
end

--
-- Rules
--

function Sage:add_rule(name, match_fn, fire_fn, kinds)
	self.rules[#self.rules + 1] = {
		name = name,
		match = match_fn,
		fire = fire_fn,
		kinds = kinds,
	}
end

function Sage:add_ruleset(ruleset)
	if ruleset.init then ruleset.init(self) end
	for _, r in ipairs(ruleset.rules or ruleset) do
		self:add_rule(r.name, r.match, r.fire)
	end
end

--
-- Pattern matching
--

-- returns true if fact matches all key/value pairs in pattern
local function matches(fact, pattern)
	for k, v in pairs(pattern) do
		if fact[k] ~= v then return false end
	end
	return true
end

-- returns all facts matching pattern, optionally sorted
function Sage:query(pattern, opts)
	opts = opts or {}
	local out = {}
	for _, fact in ipairs(self.facts) do
		if matches(fact, pattern) then
			out[#out + 1] = fact
		end
	end
	if opts.sort_by then
		local key = opts.sort_by
		local desc = opts.desc ~= false -- default descending
		table.sort(out, function(a, b)
			if a[key] == b[key] then return a.id < b.id end
			return desc and (a[key] > b[key]) or (a[key] < b[key])
		end)
	end
	if opts.limit then
		local trimmed = {}
		for i = 1, math.min(opts.limit, #out) do trimmed[i] = out[i] end
		return trimmed
	end
	return out
end

-- convenience: last n facts matching pattern, sorted descending by sort_by
function Sage:last_n(pattern, n, sort_by)
	return self:query(pattern, { sort_by = sort_by or "iter", desc = true, limit = n })
end

function Sage:last_one(pattern, sort_by)
	local r = self:last_n(pattern, 1, sort_by)
	return r[1]
end

--
-- Caches (opt-in indexed lookup, populated by rules)
--

function Sage:_update_caches(fact)
	for _, cache in pairs(self._caches) do
		local key = cache.key_fn(fact)
		if key then
			local bucket = cache.index[key] or {}
			bucket[#bucket + 1] = fact
			cache.index[key] = bucket
		end
	end
end

-- ensures a cache exists lazily, safe to call multiple times
function Sage:ensure_cache(name, key_fn)
	if not self._caches[name] then
		self._caches[name] = { index = {}, key_fn = key_fn }

		-- backfill any existing facts that should belong
		for _, fact in ipairs(self.facts) do
			local key = key_fn(fact)
			if key then
				local bucket = self._caches[name].index[key] or {}
				bucket[#bucket + 1] = fact
				self._caches[name].index[key] = bucket
			end
		end
	end
end

-- query a cache bucket directly — O(1) lookup, O(k) scan of bucket
function Sage:cache_query(name, key, opts)
	local cache = self._caches[name]
	assert(cache, "sage: no cache '" .. name .. "'")
	local bucket = cache.index[key] or {}
	if not opts then return bucket end
	local out = {}
	for _, f in ipairs(bucket) do out[#out + 1] = f end

	if opts.sort_by then
		local k = opts.sort_by
		local desc = opts.desc ~= false

		table.sort(out, function(a, b)
			if a[k] == b[k] then return a.id < b.id end
			if desc then return a[k] > b[k] end
			return a[k] < b[k]
		end)
	end
	if opts.limit then
		local trimmed = {}
		for i = 1, math.min(opts.limit, #out) do trimmed[i] = out[i] end
		return trimmed
	end
	return out
end

--
-- Combinators
--

function Sage.match_all(...)
	local fns = { ... }
	return function(f)
		for _, fn in ipairs(fns) do
			if not fn(f) then return false end
		end
		return true
	end
end

function Sage.match_any(...)
	local fns = { ... }
	return function(f)
		for _, fn in ipairs(fns) do
			if fn(f) then return true end
		end
		return false
	end
end

function Sage.match(pattern)
	return function(f)
		for k, v in pairs(pattern) do
			if f[k] ~= v then return false end
		end
		return true
	end
end

--
-- API
--

Sage._doc = "Lightweight rule engine with forward-chaining propagation, pattern queries, and indexed caches."

Sage._doc_subsection = [[
Assert or derive facts into the engine; rules fire automatically via _propagate.
Use query or cache_query to read facts back. Rules produce actions via push_action;
the orchestrator drains them with pop_actions.]]

Sage._api = {
	new = { args = "()", ret = "Sage", doc = "Create a new empty Sage engine." },
	match = {
		args = "(pattern:table)",
		ret = "fn(fact)->bool",
		doc = "Return a predicate that checks all pattern key/value pairs against a fact.",
	},
	match_all = {
		args = "(...fns)",
		ret = "fn(fact)->bool",
		doc = "Compose predicates with AND; returns false on the first failure.",
	},
	match_any = {
		args = "(...fns)",
		ret = "fn(fact)->bool",
		doc = "Compose predicates with OR; returns true on the first success.",
	},
}

Sage._types = {
	Sage = {
		doc = "Rule engine instance; holds facts, rules, caches, and a pending action queue.",
		constructor = "Sage.new()",
		kind = "table",
		methods = {
			assert = {
				args = "(self, fact:table)",
				ret = "nil",
				doc = "Add a ground fact and propagate it through all matching rules.",
			},
			derive = {
				args = "(self, fact:table, support_ids:int|int[])",
				ret = "nil",
				doc = "Add a derived fact with provenance and propagate it.",
			},
			derive_once = {
				args = "(self, key:string, fact:table, support_ids:int|int[])",
				ret = "bool",
				doc = "Derive a fact only if key has not been derived before; returns false if skipped.",
			},
			push_action = {
				args = "(self, action:table)",
				ret = "nil",
				doc = "Enqueue an action for the orchestrator to consume.",
			},
			pop_actions = {
				args = "(self)",
				ret = "table",
				doc = "Return and clear the pending action queue.",
			},
			add_rule = {
				args = "(self, name:string, match_fn:fn, fire_fn:fn, kinds:table?)",
				ret = "nil",
				doc = "Register a rule; kinds is an optional set of fact.kind strings for fast dispatch.",
			},
			add_ruleset = {
				args = "(self, ruleset:table)",
				ret = "nil",
				doc = "Register a table of rules; calls ruleset.init(self) if present.",
			},
			query = {
				args = "(self, pattern:table, opts:table?) -> table",
				ret = "fact[]",
				doc = "Return all facts matching pattern. opts: { sort_by, desc, limit }.",
			},
			last_n = {
				args = "(self, pattern:table, n:int, sort_by:string?)",
				ret = "fact[]",
				doc = "Return the n most recent facts matching pattern, sorted descending by sort_by (default 'iter').",
			},
			last_one = {
				args = "(self, pattern:table, sort_by:string?)",
				ret = "fact?",
				doc = "Return the single most recent fact matching pattern, or nil.",
			},
			ensure_cache = {
				args = "(self, name:string, key_fn:fn)",
				ret = "nil",
				doc = "Register an indexed cache on key_fn; backfills existing facts on first call.",
			},
			cache_query = {
				args = "(self, name:string, key:any, opts:table?)",
				ret = "fact[]",
				doc = "O(1) bucket lookup in a named cache. opts: { sort_by, desc, limit }.",
			},
		},
	},
}

return Sage
