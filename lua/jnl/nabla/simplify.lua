-- jnl/nabla/simplify.lua - constant folding/algebraic simplification of nodes

-- deps
local Node = require("jnl.nabla.node")

--
-- Helpers
--

local function factor_name(f)
	if (f.kind == "symbol" or f.kind == "constant") and f.rank == 0 then
		return f.name -- nil for anonymous constants, string for named
	end
	if f.kind == "pow"
		and (f.a.kind == "symbol" or f.a.kind == "constant")
		and f.a.rank == 0 then
		return f.a.name
	end
	return nil
end

--
-- Simplification
--

local function collect_factors(node)
	local factors = node:flatten("mul")
	local product = 1
	local exps, base_of, order, others = {}, {}, {}, {}

	for _, f in ipairs(factors) do
		if f:is_anon_const() then
			product = product * f.a
		else
			local name = factor_name(f)

			if name then
				local exp = f.kind == "pow" and f.b or Node.const(1)
				if exps[name] then
					exps[name] = Node.add(exps[name], exp)
				else
					exps[name] = exp
					base_of[name] = f.kind == "pow" and f.a or f
					order[#order + 1] = name
				end
			else
				others[#others + 1] = f
			end
		end
	end
	return product, exps, base_of, order, others
end

-- rebuild a flat factor list into a mul tree
local function build_mul(product, exps, base_of, order, others)
	local parts = {}
	if product ~= 1 then parts[#parts + 1] = Node.const(product) end

	for _, name in ipairs(order) do
		local e = exps[name]
		if e and not e:is_zero() then
			if e:is_one() then
				parts[#parts + 1] = base_of[name]
			else
				parts[#parts + 1] = setmetatable({ kind = "pow", a = base_of[name], b = e, rank = 0 }, Node)
			end
		end
	end

	for _, o in ipairs(others) do parts[#parts + 1] = o end

	if #parts == 0 then return Node.const(1) end
	if #parts == 1 then return parts[1] end

	local result = parts[1]
	for i = 2, #parts do
		result = Node.multiply(result, parts[i])
	end

	return result
end

local simplify -- forward declare for mutual recursion with sub-cases

local function simplify_add(a, b)
	local terms = Node.flatten(setmetatable({ kind = "add", a = a, b = b }, Node), "add")
	local sum = 0
	local non_const = {}

	for _, t in ipairs(terms) do
		if t:is_anon_const() then
			sum = sum + t.a
		else
			non_const[#non_const + 1] = t
		end
	end

	if #non_const == 0 then return Node.const(sum) end

	local result = non_const[1]
	for i = 2, #non_const do
		result = setmetatable({ kind = "add", a = result, b = non_const[i], rank = non_const[i].rank }, Node)
	end

	if sum ~= 0 then
		result = setmetatable({ kind = "add", a = result, b = Node.const(sum), rank = result.rank }, Node)
	end
	return result
end

local function simplify_mul(a, b)
	local factors = Node.flatten(setmetatable({ kind = "mul", a = a, b = b }, Node), "mul")
	local product = 1
	local exps, base_of, order, others = {}, {}, {}, {}

	for _, f in ipairs(factors) do
		if f:is_anon_const() then
			product = product * f.a
			if product == 0 then return Node.const(0) end
		else
			local name = factor_name(f)

			if name then
				local exp = f.kind == "pow" and f.b or Node.const(1)
				if exps[name] then
					exps[name] = Node.add(exps[name], exp)
				else
					exps[name] = exp
					base_of[name] = f.kind == "pow" and f.a or f
					order[#order + 1] = name
				end
			else
				others[#others + 1] = f
			end
		end
	end

	-- simplify accumulated exponents before rebuilding
	for _, name in ipairs(order) do
		exps[name] = simplify(exps[name])
	end
	return build_mul(product, exps, base_of, order, others)
end

local function simplify_div(a, b)
	local np, n_exps, n_base, n_order, n_others = collect_factors(a)
	local dp, d_exps, d_base, d_order, d_others = collect_factors(b)

	local scalar = np / dp

	-- cancel: subtract denominator exponents from numerator
	for _, name in ipairs(d_order) do
		if n_exps[name] then
			n_exps[name] = simplify(Node.subtract(n_exps[name], d_exps[name]))
		end
	end

	-- remaining denominator: names absent from numerator
	local d_rem_exps, d_rem_order = {}, {}
	for _, name in ipairs(d_order) do
		if not n_exps[name] then
			d_rem_exps[name] = d_exps[name]
			d_rem_order[#d_rem_order + 1] = name
		end
	end

	local num = build_mul(scalar, n_exps, n_base, n_order, n_others)
	local den = build_mul(1, d_rem_exps, d_base, d_rem_order, d_others)

	if den:is_one() then return num end
	return setmetatable({ kind = "div", a = num, b = den, rank = num.rank }, Node)
end

simplify = function(node)
	if node:is_leaf() then return node end

	local a = simplify(node.a)
	local b = node.b and simplify(node.b)
	local k = node.kind

	if k == "add" then
		return simplify_add(a, b)
	elseif k == "mul" then
		return simplify_mul(a, b)
	elseif k == "div" then
		return simplify_div(a, b)
	else
		local n = {}
		for key, v in pairs(node) do n[key] = v end
		n.a = a
		if b then n.b = b end
		return setmetatable(n, Node)
	end
end

return simplify
