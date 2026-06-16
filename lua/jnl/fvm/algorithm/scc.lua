-- lua/jnl/fvm/algorithm/scc.lua - SCC detection on the registry field dependency graph.
-- <jed@nelson.ac> // 2026-06-16

--- Results of SCC detection and field classification.
---@class SCCResult
---@field groups     SCCGroup[]  All groups in topological solve order.
---@field coupled    SCCGroup[]  Groups requiring an explicit resolution strategy.
---@field sequential SCCGroup[]  Groups solvable in default topological order.

--- One strongly connected component among the registry's prognostic fields.
---
--- Fields are sorted alphabetically for a canonical, deterministic representation.
---@class SCCGroup
---@field fields  string[]              Fields in this component.
---@field kind    "coupled"|"sequential"
---@field n_edges integer               Internal dependency edge count.

---@private
local M = {}

--
-- Graph construction
--

-- Build edges[name] = {dep, ...} where dep is a prognostic field read by
-- name's governing equation. Non-prognostic dependencies (diagnostics,
-- constants, fields without a governing equation) are excluded because they
-- do not participate in the iterative solve loop.
local function build_graph(reg)
	local prognostics = reg:prognostics()
	local prog_set    = {}
	for _, name in ipairs(prognostics) do prog_set[name] = true end

	local edges = {}

	for _, name in ipairs(prognostics) do
		edges[name]    = {}
		local deps     = reg:deps_of(name)
		local all_deps = {}
		for dep in pairs(deps.equation.value) do all_deps[dep] = true end
		for dep in pairs(deps.equation.matrix) do all_deps[dep] = true end

		for dep in pairs(all_deps) do
			if prog_set[dep] then
				edges[name][#edges[name] + 1] = dep
			end
		end
	end

	return prognostics, edges
end

--
-- Tarjan's SCC algorithm
--
-- For the graph convention where edges[A] = {B,...} means "A reads B",
-- this produces SCCs in topological solve order: each SCC appears after
-- all SCCs whose fields it depends upon, so iterating the result in order
-- gives a valid solve sequence.
--
-- Safe for registry sizes up to a few hundred fields; recursion depth is
-- bounded by the longest DFS path through the dependency graph.
--

local function tarjan(nodes, edges)
	local counter  = 0
	local stack    = {}
	local on_stack = {}
	local idx      = {}
	local lowlink  = {}
	local sccs     = {}

	local function visit(v)
		idx[v]            = counter
		lowlink[v]        = counter
		counter           = counter + 1
		stack[#stack + 1] = v
		on_stack[v]       = true

		for _, w in ipairs(edges[v] or {}) do
			if not idx[w] then
				visit(w)
				if lowlink[w] < lowlink[v] then lowlink[v] = lowlink[w] end
			elseif on_stack[w] then
				if idx[w] < lowlink[v] then lowlink[v] = idx[w] end
			end
		end

		if lowlink[v] == idx[v] then
			local scc = {}
			repeat
				local w       = stack[#stack]
				stack[#stack] = nil
				on_stack[w]   = false
				scc[#scc + 1] = w
			until w == v
			sccs[#sccs + 1] = scc
		end
	end

	for _, v in ipairs(nodes) do
		if not idx[v] then visit(v) end
	end

	return sccs
end

--
-- Classification
--

local function count_internal(fields, edges)
	local set = {}
	for _, name in ipairs(fields) do set[name] = true end
	local n = 0
	for _, name in ipairs(fields) do
		for _, dep in ipairs(edges[name] or {}) do
			if set[dep] then n = n + 1 end
		end
	end
	return n
end

-- A genuine SCC has more than one field. Singleton SCCs cannot have
-- self-edges in practice because the registry scan excludes self-name
-- dependencies during equation lowering; so all singletons are sequential.
local function build_groups(raw_sccs, edges)
	local groups     = {}
	local coupled    = {}
	local sequential = {}

	for _, scc in ipairs(raw_sccs) do
		local fields = {}
		for _, name in ipairs(scc) do fields[#fields + 1] = name end
		table.sort(fields)

		local kind          = #fields > 1 and "coupled" or "sequential"
		local group         = {
			fields  = fields,
			kind    = kind,
			n_edges = count_internal(fields, edges),
		}

		groups[#groups + 1] = group

		if kind == "coupled" then
			coupled[#coupled + 1] = group
		else
			sequential[#sequential + 1] = group
		end
	end

	return groups, coupled, sequential
end

--
-- Public API
--

--- Detect strongly connected components among a registry's prognostic fields.
---
--- Groups are returned in topological solve order: each group appears after
--- all groups it depends on. Coupled groups contain fields with mutual
--- equation dependencies and require an explicit resolution strategy via
--- Algorithm:resolve(). Sequential groups are solved automatically in order.
---@param reg Registry
---@return SCCResult
function M.detect(reg)
	local prognostics, edges = build_graph(reg)

	if #prognostics == 0 then
		return { groups = {}, coupled = {}, sequential = {} }
	end

	local raw                         = tarjan(prognostics, edges)
	local groups, coupled, sequential = build_groups(raw, edges)

	return { groups = groups, coupled = coupled, sequential = sequential }
end

--- Return a human-readable listing of detection results.
---@param result SCCResult
---@return string
function M.listing(result)
	if #result.groups == 0 then
		return "(no prognostic fields)"
	end

	local lines = {}

	for i, g in ipairs(result.groups) do
		lines[#lines + 1] = string.format("  group %d  [%s]  {%s}  edges=%d",
			i, g.kind, table.concat(g.fields, ", "), g.n_edges)
	end

	lines[#lines + 1] = string.format(
		"  %d coupled (need resolution)  %d sequential",
		#result.coupled, #result.sequential)

	return table.concat(lines, "\n")
end

return M
