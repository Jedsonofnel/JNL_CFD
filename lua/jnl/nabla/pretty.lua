-- jnl/nabla/pretty.lua - node pretty printing

-- deps
local G = require("jnl.core.glyphs")
local Node = require("jnl.nabla.node")
local Acc = require("jnl.nabla.accessor")

--
-- Precendence
--

local PREC = {
	add = 1,
	sub = 1,
	mul = 2,
	div = 2,
	neg = 3, -- unary
	pow = 4,
}

local ASSOC = {
	add = "left",
	sub = "left",
	mul = "left",
	div = "left",
	pow = "right",
}

local function needs_parens(child, parent_prec, is_right_child)
	local cp = PREC[child.kind]
	if not cp then return false end

	if cp < parent_prec then return true end

	-- same prec, right side of left-assoc
	-- e.g. a-(b+c) needs parens
	if cp == parent_prec and is_right_child
		and ASSOC[child.kind] == "left" then
		return true
	end
	return false
end

local node_pretty

local function wrap(s, node, parent_prec, is_right)
	if needs_parens(node, parent_prec, is_right) then
		return G.lparen .. s .. G.rparen
	end
	return s
end

local function op_arg(node)
	if node:is_leaf() then
		return node_pretty(node, 0, false)
	else
		return G.lparen .. node_pretty(node, 0, false) .. G.rparen
	end
end

node_pretty = function(node, parent_prec, is_right)
	node = Node.from(node)
	parent_prec = parent_prec or 0
	is_right = is_right or false
	local k = node.kind

	if k == "symbol" then
		local pre = node.name:match("(.+)_prime$")
		return pre and (pre .. "'") or node.name
	elseif k == "constant" then
		if node.name then return node.name end
		if node.a < 0 then
			return G.lparen .. string.format("%g", node.a) .. G.rparen
		end
		return string.format("%g", node.a)
	elseif k == "cvec" then
		local n = (node.a[3] ~= 0) and 3 or 2
		local parts = {}
		for i = 1, n do parts[i] = string.format("%g", node.a[i]) end
		return G.lbracket .. table.concat(parts, ", ") .. G.rbracket
	elseif k == "component" then
		local axis = Node.AXES[node.b.a]
		local base = node.a:is_leaf()
			and node_pretty(node.a, 0, false)
			or G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
		return base .. G.subscript(axis)

		-- mathematical ops
	elseif k == "neg" then
		local s = G.neg .. node_pretty(node.a, PREC.neg, false)
		return wrap(s, node, parent_prec, is_right)
	elseif k == "add" then
		local terms = node:flatten("add")
		local parts = {}
		for _, t in ipairs(terms) do
			parts[#parts + 1] = node_pretty(t, PREC.add, false)
		end
		return wrap(table.concat(parts, G.add), node, parent_prec, is_right)
	elseif k == "sub" then
		local parts = { node_pretty(node.a, PREC.sub, false) }
		local subtrahends = node.b:flatten("add")
		for _, t in ipairs(subtrahends) do
			parts[#parts + 1] = node_pretty(t, PREC.sub, true)
		end
		return wrap(table.concat(parts, G.sub), node, parent_prec, is_right)
	elseif k == "mul" then
		local factors = node:flatten("mul")
		local parts = {}
		for i, f in ipairs(factors) do
			local s = node_pretty(f, PREC.mul, false)
			local prev = factors[i - 1]
			if i == 1 then
				parts[#parts + 1] = s
			elseif prev and prev:is_anon_const() and f.kind == "symbol" then
				parts[#parts + 1] = s
			else
				parts[#parts + 1] = G.mul .. s
			end
		end
		return wrap(table.concat(parts, ""), node, parent_prec, is_right)
	elseif k == "div" then
		local q = node_pretty(node.a, PREC.div, false)
		local d = node_pretty(node.b, PREC.div, true)
		return wrap(q .. G.div_op .. d, node, parent_prec, is_right)
	elseif k == "pow" then
		local base_s = node_pretty(node.a, PREC.pow, false)
		if node.b.kind == "constant" and not node.b.name then
			local e = node.b.a
			if e == math.floor(e) then
				return wrap(base_s .. G.superscript_int(e), node, parent_prec, is_right)
			end
		end
		local exp_s = node_pretty(node.b, PREC.pow + 1, false)
		return wrap(base_s .. G.pow .. exp_s, node, parent_prec, is_right)

		-- gradient ops
	elseif k == "grad" then
		return G.grad .. op_arg(node.a)
	elseif k == "divergence" then
		return G.div .. op_arg(node.a)
	elseif k == "laplacian" then
		return G.lap .. op_arg(node.a)
	elseif k == "ddt" then
		return G.ddt .. op_arg(node.a)
	elseif k == "curl" then
		return G.curl .. op_arg(node.a)
	elseif k == "symm" then
		return "sym" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "skew" then
		return "skw" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "dev" then
		return "dev" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "trace" then
		return "tr" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "transpose" then
		return node_pretty(node.a, PREC.pow, false) .. G.transpose
	elseif k == "mag" then
		return "|" .. node_pretty(node.a, 0, false) .. "|"
	elseif k == "inv" then
		return node_pretty(node.a, PREC.pow, false) .. G.superscript_int(-1)
	elseif k == "matvec" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.dot .. rhs, node, parent_prec, is_right)
	elseif k == "matmul" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.dot .. rhs, node, parent_prec, is_right)

		-- vector calc
	elseif k == "scale" then
		local s = node_pretty(node.a, PREC.mul, false)
		local f = node_pretty(node.b, PREC.mul, false)
		local sep = node.a:is_anon_const() and node.b.kind == "symbol" and "" or G.mul
		return wrap(s .. sep .. f, node, parent_prec, is_right)
	elseif k == "dot" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.dot .. rhs, node, parent_prec, is_right)
	elseif k == "outer" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.otimes .. rhs, node, parent_prec, is_right)
	elseif k == "cross" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.cross .. rhs, node, parent_prec, is_right)
	elseif k == "ddot" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.ddot .. rhs, node, parent_prec, is_right)
	end

	local acc_spec = Acc.get(k)
	if acc_spec then
		return acc_spec.pretty(node, G)
	end

	return string.format("<?:%s>", node.kind)
end

return node_pretty
