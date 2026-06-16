-- jnl/nabla/deps.lua

---@private
local M = {}

local function deps_direct(reg, name)
	local e = reg:entry(name)
	if not e then return {} end
	return reg:deps_of(name).equation.value
end

-- full transitive closure — for classify and has_mutable
local function deps_transitive(reg, name, seen)
	seen = seen or {}
	if seen[name] then return seen end
	seen[name] = true
	for dep in pairs(deps_direct(reg, name)) do
		deps_transitive(reg, dep, seen)
	end
	return seen
end

-- stops at prognostic boundaries — for invalidation only
local function deps_transitive_invalidation(reg, name, seen)
	seen = seen or {}
	if seen[name] then return seen end
	seen[name] = true
	local e = reg:entry(name)
	if e and e.solve == true then return seen end
	for dep in pairs(deps_direct(reg, name)) do
		deps_transitive_invalidation(reg, dep, seen)
	end
	return seen
end

local function topo_visit(reg, name, allowed, state)
	if not allowed[name] or state.visiting[name] or state.emitted[name] then return end
	state.visiting[name] = true
	for dep in pairs(deps_direct(reg, name)) do
		topo_visit(reg, dep, allowed, state)
	end
	state.visiting[name]            = false
	state.emitted[name]             = true
	state.result[#state.result + 1] = name
end

local function topo_sort(reg, names)
	local allowed = {}
	for _, n in ipairs(names) do allowed[n] = true end
	local state = { result = {}, visiting = {}, emitted = {} }
	for _, n in ipairs(names) do topo_visit(reg, n, allowed, state) end
	return state.result
end

local function is_mutable(entry)
	if not entry then return false end
	return entry.solve == true or (entry.correction ~= nil and not entry.is_prescribed)
end

local function has_mutable(reg, name)
	if is_mutable(reg:entry(name)) then return true end
	local tdeps = deps_transitive(reg, name, {})
	for dep in pairs(tdeps) do
		if dep ~= name and is_mutable(reg:entry(dep)) then return true end
	end
	return false
end

local function classify(reg, explicit_set)
	local anchor_reach = {}
	for anchor in pairs(explicit_set) do
		for dep in pairs(deps_transitive(reg, anchor, {})) do
			if not explicit_set[dep] then anchor_reach[dep] = true end
		end
	end

	local pre, main, post = {}, {}, {}
	reg:each(function(name, entry)
		if explicit_set[name] then return end
		if entry.kind == "const" then return end
		local mutable = has_mutable(reg, name)
		if anchor_reach[name] then
			if mutable then main[#main + 1] = name else pre[#pre + 1] = name end
		else
			if mutable then post[#post + 1] = name else pre[#pre + 1] = name end
		end
	end)

	return pre, main, post
end

M = {
	deps_direct = deps_direct,
	deps_transitive = deps_transitive,
	deps_transitive_invalidation = deps_transitive_invalidation,
	topo_sort = topo_sort,
	is_mutable = is_mutable,
	has_mutable = has_mutable,
	classify = classify,
}

return M
