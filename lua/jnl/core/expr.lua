-- core/expr.lua - arbitrary arithmetic expression graphs
-- <jed@nelson.ac> // 2026-05-11

local M = {}

local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")

---@class Expr
local Expr = {}
Expr.__index = Expr

---@param v any
---@return boolean
local function is_expr(v)
	return type(v) == "table" and getmetatable(v) == Expr
end

M.is_expr = is_expr

--
-- Dependency constructors
--

---@param e Expr|any
---@param into table<string,true>?
---@return table<string,true>
local function collect_deps(e, into)
	into = into or {}
	if type(e) ~= "table" then return into end

	if e.kind == "sym" then
		into[e.name] = true
		return into
	end

	if e.kind == "intermediate" then
		into[e.name] = true
		return into
	end

	if e._dep_name then
		into[e._dep_name] = true
		return into
	end

	-- recurse
	collect_deps(e.a, into)
	collect_deps(e.b, into)
	collect_deps(e.base, into)
	collect_deps(e.exp, into)
	collect_deps(e.value, into) -- negation

	-- variadic
	if e.addends then
		for _, child in ipairs(e.addends) do collect_deps(child, into) end
	end
	if e.factors then
		for _, child in ipairs(e.factors) do collect_deps(child, into) end
	end

	return into
end

M.collect_deps = collect_deps

---@param t table
---@return Expr
local function make_expr(t)
	t._deps = collect_deps(t)
	return setmetatable(t, Expr)
end

M.make_expr = make_expr

--
-- Coercion
--

---Coerce a number, string, or Expr to an Expr.
---@param v number|string|Expr
---@return Expr
local function from(v)
	if type(v) == "number" then
		return make_expr { kind = "const", value = v, _type = "expr" }
	elseif type(v) == "string" then
		assert(not v:match("^__"),
			"symbol names starting with '__' are reserved: " .. v)
		return make_expr { kind = "sym", name = v, _type = "expr" }
	elseif is_expr(v) then
		return v
	else
		error("E.from: cannot coerce to expr: " .. tostring(v), 3)
	end
end

M.from = from

--
-- Constructors
--

---@param name string
---@return Expr
function M.sym(name)
	V.identifier(name, "E.sym")
	return make_expr { kind = "sym", name = name }
end

---@param value number
---@return Expr
function M.const(value)
	V.typeof(value, "number", "E.const")
	return make_expr { kind = "const", value = value }
end

-- Arithmetic


---@param ... number|string|Expr
---@return Expr
function M.add(...)
	local args = { ... }
	if #args == 1 then
		return from(args[1])
	elseif #args == 2 then
		local a, b = from(args[1]), from(args[2])
		return make_expr { kind = "add", a = a, b = b }
	end

	-- variadic add (ignoring zeros, the identity)
	local addends = {}
	for _, v in ipairs(args) do
		local addend = from(v)
		if not (addend.kind == "const" and addend.value == 0) then
			addends[#addends + 1] = addend
		end
	end
	return make_expr { kind = "addv", addends = addends }
end

---@param a number|string|Expr
---@param b number|string|Expr
---@return Expr
function M.sub(a, b)
	return make_expr { kind = "sub", a = from(a), b = from(b) }
end

---@param ... number|string|Expr
---@return Expr
function M.mul(...)
	local args = { ... }
	if #args == 1 then
		return from(args[1])
	elseif #args == 2 then
		local a, b = from(args[1]), from(args[2])
		return make_expr { kind = "mul", a = a, b = b }
	end

	-- variadic mul
	local factors = {}
	for _, v in ipairs(args) do
		local factor = from(v)
		if not (factor.kind == "const" and factor.value == 1) then
			factors[#factors + 1] = factor
		end
	end
	return make_expr { kind = "mulv", factors = factors }
end

---@param a number|string|Expr
---@param b number|string|Expr
---@return Expr
function M.div(a, b)
	a, b = from(a), from(b)
	return make_expr { kind = "div", a = a, b = b }
end

---@param a number|string|Expr
---@return Expr
function M.neg(a)
	a = from(a)
	return make_expr { kind = "neg", value = a }
end

---@param base number|string|Expr
---@param exp  number|string|Expr
---@return Expr
function M.pow(base, exp)
	base, exp = from(base), from(exp)
	return make_expr { kind = "pow", base = base, exp = exp }
end

-- Mesh access

---Cell centre x coordinate.
---@return Expr
function M.cx()
	return make_expr { kind = "cell_x" }
end

---Cell centre y coordinate.
---@return Expr
function M.cy()
	return make_expr { kind = "cell_y" }
end

---Cell volume
---@return Expr
function M.cV()
	return make_expr { kind = "cell_vol" }
end

--
-- Internal name manglers
--

---@param field string
local function prime_sym(field) return "__prime_" .. field end
---@param field string
local function expl_sym(field) return "__expl_" .. field end
---@param field string
local function prev_sym(field) return "__prev_" .. field end

---@param name string
local function is_prime(name) return name:match("^__prime_(.+)$") end
---@param name string
local function is_expl(name) return name:match("^__expl_(.+)$") end
---@param name string
local function is_prev(name) return name:match("^__prev_(.+)$") end

-- for overwriting
M.pretty_sym_fallback = nil

local function pretty_sym(name)
	if type(name) ~= "string" then
		return tostring(name)
	end
	local b
	b = is_prime(name); if b then return b .. G.prime end
	b = is_expl(name); if b then return b .. G.expl end
	b = is_prev(name); if b then return b .. G.prev end
	if M.pretty_sym_fallback then
		local r = M.pretty_sym_fallback(name)
		if r then return r end
	end
	return name
end

M.prime_name = prime_sym
M.expl_name  = expl_sym
M.prev_name  = prev_sym
M.is_prime   = is_prime
M.is_expl    = is_expl
M.is_prev    = is_prev
M.pretty_sym = pretty_sym

---Explicit (linearised) value of field at the previous outer iteration.
---@param field string
---@return Expr
function M.prime(field)
	V.identifier(field, "E.prime")
	return make_expr {
		kind      = "prime",
		field     = field,
		_dep_name = prime_sym(field),
		_pretty   = function() return field .. G.prime end,
	}
end

---Explicit (lagged) value of field, held fixed during inner iterations.
---@param field string
---@return Expr
function M.expl(field)
	V.identifier(field, "E.expl")
	return make_expr {
		kind      = "expl",
		field     = field,
		_dep_name = expl_sym(field),
		_pretty   = function() return field .. G.expl end,
	}
end

---Value of field from the previous time step.
---@param field string
---@return Expr
function M.prev(field)
	V.identifier(field, "E.prev")
	return make_expr {
		kind      = "prev",
		field     = field,
		_dep_name = prev_sym(field),
		_pretty   = function() return field .. G.prev end,
	}
end

--
-- Expression printing (surprisingly involved)
--

local PREC  = {
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
	if cp < parent_prec then return true end -- strictly lower: always paren
	if cp == parent_prec and is_right_child -- same prec, right side of left-assoc
		and ASSOC[child.kind] == "left" then
		return true                       -- e.g. a-(b+c) needs parens
	end
	return false
end

local function pretty_pow(base_str, exp_node)
	if G._unicode
		and exp_node.kind == "const"
		and exp_node.value == math.floor(exp_node.value)
		and math.abs(exp_node.value) <= 9
	then
		return base_str .. G.superscript_int(exp_node.value)
	end
	return base_str .. G.pow .. M.pretty(exp_node, PREC.pow + 1, false)
end

---Render an expression to a human-readable string.
---Exposed as both M.pretty(e) and Expr:pretty() — the free function form is
---used internally for recursive calls with explicit precedence arguments.
---@param e Expr|number
---@param parent_prec  integer|nil
---@param is_right_child boolean|nil
---@return string
function M.pretty(e, parent_prec, is_right_child)
	parent_prec = parent_prec or 0
	is_right_child = is_right_child or false

	if type(e) == "number" then
		return string.format("%g", e)
	end

	assert(type(e) == "table", "E.pretty: expected expr table, got " .. type(e))

	local function wrap(s)
		if needs_parens(e, parent_prec, is_right_child) then
			return G.lparen .. s .. G.rparen
		end
		return s
	end

	local k = e.kind

	if k == "sym" then
		return pretty_sym(e.name)
	elseif k == "const" then
		local n = e.value
		if n < 0 then
			return G.lparen .. string.format("%g", n) .. G.rparen
		end
		return string.format("%g", n)

		-- system access
	elseif k == "cell_x" then
		return "<cx>"
	elseif k == "cell_y" then
		return "<cy>"
	elseif k == "cell_vol" then
		return "<cV>"

		-- Unary
	elseif k == "neg" then
		local inner = M.pretty(e.value, PREC.neg, false)
		local needs_wrap = e.value.kind ~= "sym"
			and e.value.kind ~= "const"
			and e.value.kind ~= "prev"
		if needs_wrap then
			inner = G.lparen .. inner .. G.rparen
		end
		return wrap(G.neg .. inner)

		-- binary ops
	elseif e.kind == "add" then
		local p = PREC.add
		return wrap(M.pretty(e.a, p, false) .. G.add .. M.pretty(e.b, p, true))
	elseif e.kind == "sub" then
		local p = PREC.sub
		return wrap(M.pretty(e.a, p, false) .. G.sub .. M.pretty(e.b, p, true))
	elseif e.kind == "mul" then
		local p = PREC.mul
		local lhs = M.pretty(e.a, p, false)
		local rhs = M.pretty(e.b, p, true)
		local sep = (e.a.kind == "const" and e.b.kind == "sym") and "" or G.mul
		return wrap(lhs .. sep .. rhs)
	elseif e.kind == "div" then
		local p = PREC.div
		return wrap(M.pretty(e.a, p, false) .. G.div_op .. M.pretty(e.b, p, true))
	elseif k == "pow" then
		local base = M.pretty(e.base, PREC.pow, false)
		return wrap(pretty_pow(base, e.exp))

		-- variadic add and mul
	elseif k == "addv" then
		local parts = {}
		for _, addend in ipairs(e.addends) do
			parts[#parts + 1] = M.pretty(addend, PREC.add, false)
		end
		return wrap(table.concat(parts, G.add))
	elseif k == "mulv" then
		local parts = {}
		for i, factor in ipairs(e.factors) do
			local s = M.pretty(factor, PREC.mul, false)
			local prev = e.factors[i - 1]
			local sep = (i > 1 and prev and prev.kind == "const"
				and factor.kind == "sym") and "" or G.mul
			parts[#parts + 1] = (i == 1 and "" or sep) .. s
		end
		return wrap(table.concat(parts, ""))

		-- name manglers added for explicitness
	elseif k == "prime" or k == "expl" or k == "prev" then
		return e._pretty()
	end

	-- for externally defined expressions
	if e._pretty ~= nil then
		return e._pretty()
	end

	return "<?:" .. tostring(k) .. ">" -- fallback
end

--
-- Scratch depth (Sethi-Ullman)
--

---Compute the number of scratch buffers needed to evaluate this expression,
---using the Sethi-Ullman register allocation algorithm.  Call before
---allocating a scratch pool to ensure sufficient capacity.
---@param e Expr|any
---@return integer
local function scratch_depth(e)
	if type(e) ~= "table" then return 1 end -- bare number -> CONST
	local k = e.kind
	if k == "const" then return 1 end
	if k == "sym" or k == "prime" or k == "expl" or k == "prev"
		or k == "cell_x" or k == "cell_y" or k == "cell_vol" then
		return 0 -- all become EXPR_ARRAY in C, no scratch consumed
	end
	if k == "neg" then
		return scratch_depth(e.value)
	end
	if k == "add" or k == "sub" or k == "mul" or k == "div" or k == "pow" then
		local da, db = scratch_depth(e.a), scratch_depth(e.b)
		if da >= db then
			return math.max(da, db + 1) + 1
		else
			return math.max(db, da + 1) + 1
		end
	end
	if k == "addv" then
		local d = scratch_depth(e.addends[1])
		for i = 2, #e.addends do
			local di = scratch_depth(e.addends[i])
			d = (d >= di) and d or (di + 1)
		end
		return d
	end
	if k == "mulv" then
		local d = scratch_depth(e.factors[1])
		for i = 2, #e.factors do
			local di = scratch_depth(e.factors[i])
			d = (d >= di) and d or (di + 1)
		end
		return d
	end
	if e._scratch_depth ~= nil then return e._scratch_depth end
	return 0
end

M.scratch_depth = scratch_depth

--
-- Metatable methods
--

---@return integer
function Expr:scratch_depth()
	return scratch_depth(self)
end

---@return string
function Expr:pretty()
	return M.pretty(self)
end

Expr.__tostring = Expr.pretty


---Return a sorted list of field names this expression depends on.
---@return string[]
function Expr:deps()
	local set = self._deps or collect_deps(self, {})
	local names = {}
	for name in pairs(set) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

---Walk every node in the expression tree, calling visitor(node) on each.
---@param visitor fun(node: Expr)
local function walk(e, visitor)
	if type(e) ~= "table" then return end
	visitor(e)
	if e._walk then
		e._walk(e, visitor)
	else
		for _, child in ipairs({ e.a, e.b, e.base, e.exp, e.value }) do
			walk(child, visitor)
		end
		for _, key in ipairs({ "addends", "factors" }) do
			for _, child in ipairs(e[key] or {}) do walk(child, visitor) end
		end
	end
end

function Expr:walk(visitor)
	walk(self, visitor)
end

--
-- Compilation/C-interop
--

local I = require("jnl.expr_internal")

local function compile(expr_table, bindings)
	bindings = bindings or {}

	local ud = I.new()

	-- Recursively build the C node tree.  Returns a lightuserdata node ptr.
	local function build(e)
		if type(e) == "number" then
			return I.const(ud, e)
		end

		assert(is_expr(e), "compile: expected an expr, got " .. tostring(e))

		local k = e.kind

		-- Leaf nodes
		if k == "const" then
			return I.const(ud, e.value)
		elseif k == "sym" then
			local v = bindings[e.name]
			assert(v ~= nil, "expr_binding.compile: no binding for symbol '" .. e.name .. "'")
			if type(v) == "number" then
				return I.const(ud, v)
			end
			return I.array(ud, v)
		elseif k == "prime" or k == "expl" or k == "prev" then
			-- these use mangled names: e._dep_name  ("__prime_foo", etc.)
			local v = bindings[e._dep_name] or bindings[e.field]
			assert(v, "expr_binding.compile: no binding for '"
				.. (e._dep_name or e.field) .. "'")
			return I.array(ud, v)
		elseif k == "cell_x" or k == "cell_y" or k == "cell_vol" then
			local v = bindings[k]
			assert(v, "expr_binding.compile: no binding for '" .. k .. "'")
			return I.array(ud, v)

			-- Unary
		elseif k == "neg" then
			return I.neg(ud, build(e.value))

			-- Binary
		elseif k == "add" then
			return I.add(ud, build(e.a), build(e.b))
		elseif k == "sub" then
			return I.sub(ud, build(e.a), build(e.b))
		elseif k == "mul" then
			return I.mul(ud, build(e.a), build(e.b))
		elseif k == "div" then
			return I.div(ud, build(e.a), build(e.b))
		elseif k == "pow" then
			return I.pow(ud, build(e.a), build(e.b))

			-- Variadic (left-fold into binary ops)
		elseif k == "addv" then
			assert(#e.addends >= 1, "addv with no addends")
			local acc = build(e.addends[1])
			for i = 2, #e.addends do
				acc = I.add(ud, acc, build(e.addends[i]))
			end
			return acc
		elseif k == "mulv" then
			assert(#e.factors >= 1, "mulv with no factors")
			local acc = build(e.factors[1])
			for i = 2, #e.factors do
				acc = I.mul(ud, acc, build(e.factors[i]))
			end
			return acc

			-- things with _dep_name
		elseif e._dep_name then
			-- treat as array binding looked up by mangled name
			local lookup = e._comp_name or e._dep_name
			local v = bindings[lookup]
			assert(v, "expr_binding.compile: no binding for intermediate '"
				.. lookup .. "'")
			return I.array(ud, v)
		end

		-- custom node with a _compile hook
		if e._compile then
			return e._compile(ud, build, bindings)
		end

		error("expr_binding.compile: unhandled expr kind '" .. tostring(k) .. "'")
	end

	local root = build(expr_table)
	ud:set_root(root)
	return ud
end

---Compile this expression against a bindings table, caching the result.
---Must be called before eval(). Safe to call again to recompile with new bindings.
---@param bindings table<string, userdata>  Maps symbol names to vec objects
---@return Expr self  (for chaining)
function Expr:compile(bindings)
	self._ud = compile(self, bindings)
	return self
end

---Evaluate the compiled expression over n elements using the given scratch pool.
---@param pool ScratchPool  Scratch pool (from ctx:cell_pool() or ctx:face_pool())
---@param n    integer   Number of elements to evaluate over
---@return VecUD      Result vec
function Expr:eval(pool, n)
	assert(self._ud, "expr:eval called before expr:compile")
	return self._ud:eval(pool, n)
end

--
-- API
--

M._doc = "Arithmetic expression graphs for symbolic computation and C codegen."

M._doc_subsection =
	"Construct expressions with add/mul/div/neg/pow and leaves sym/const/cx/cy/cV. " ..
	"Strings and numbers coerce automatically via from(). E.prime/expl/prev create " ..
	"mangled-name references for correction and lagged quantities. Call compile(bindings) " ..
	"then eval(pool, n) to evaluate over a mesh array."

M._api = {
	-- coercion / low-level
	from          = { args = "v:number|string|Expr", ret = "Expr", doc = "Coerce number, string, or Expr to Expr" },
	make_expr     = { args = "t:table", ret = "Expr", doc = "Stamp Expr metatable onto t and collect deps into t._deps" },
	collect_deps  = { args = "e:Expr, into:table?", ret = "table<string,true>", doc = "Walk expression tree and accumulate symbol name dependencies" },
	pretty        = { args = "e:Expr", ret = "string", doc = "Render expression to string with correct operator precedence" },
	scratch_depth = { args = "e:Expr", ret = "int", doc = "Sethi-Ullman register count needed to evaluate this expression" },
	-- leaf constructors
	sym           = { args = "name:string", ret = "Expr", doc = "Named symbol reference" },
	const         = { args = "value:number", ret = "Expr", doc = "Numeric constant" },
	cx            = { args = "", ret = "Expr", doc = "Cell centre x coordinate" },
	cy            = { args = "", ret = "Expr", doc = "Cell centre y coordinate" },
	cV            = { args = "", ret = "Expr", doc = "Cell volume" },
	-- arithmetic
	add           = { args = "...:number|string|Expr", ret = "Expr", doc = "Sum; variadic; ignores zero addends" },
	sub           = { args = "a, b", ret = "Expr", doc = "Difference a - b" },
	mul           = { args = "...:number|string|Expr", ret = "Expr", doc = "Product; variadic; ignores unit factors" },
	div           = { args = "a, b", ret = "Expr", doc = "Quotient a / b" },
	neg           = { args = "a", ret = "Expr", doc = "Unary negation" },
	pow           = { args = "base, exp", ret = "Expr", doc = "base^exp" },
	-- lagged / correction references
	prime         = { args = "field:string", ret = "Expr", doc = "Pressure-correction value; dep name __prime_<field>" },
	expl          = { args = "field:string", ret = "Expr", doc = "Explicit lagged value, fixed during inner iterations; dep __expl_<field>" },
	prev          = { args = "field:string", ret = "Expr", doc = "Value from previous time step; dep __prev_<field>" },
	-- name manglers
	prime_name    = { args = "field:string", ret = "string", doc = "Return __prime_<field>" },
	expl_name     = { args = "field:string", ret = "string", doc = "Return __expl_<field>" },
	prev_name     = { args = "field:string", ret = "string", doc = "Return __prev_<field>" },
	is_prime      = { args = "name:string", ret = "string?", doc = "Return base field name if name is a prime mangling, else nil" },
	is_expl       = { args = "name:string", ret = "string?", doc = "Return base field name if name is an expl mangling, else nil" },
	is_prev       = { args = "name:string", ret = "string?", doc = "Return base field name if name is a prev mangling, else nil" },
	pretty_sym    = { args = "name:string", ret = "string", doc = "Expand mangled names to unicode glyphs for display" },
}

M._types = {
	Expr = {
		doc         = "Arithmetic expression node; all E.* constructors return Expr",
		constructor = "E.sym / E.const / E.add / E.mul / E.prime etc.",
		kind        = "table",
		methods     = {
			pretty        = { args = "", ret = "string", doc = "Render to human-readable string" },
			deps          = { args = "", ret = "string[]", doc = "Sorted symbol names this expression depends on" },
			scratch_depth = { args = "", ret = "int", doc = "Scratch buffers needed for evaluation" },
			compile       = { args = "bindings:table<string,vec>", ret = "Expr", doc = "Compile against symbol->vec bindings; required before eval()" },
			eval          = { args = "pool:ScratchPool, n:int", ret = "vec", doc = "Evaluate compiled expression over n elements" },
			walk          = { args = "visitor:fun(node:Expr)", ret = "nil", doc = "Call visitor on every node in the expression tree" },
		},
	},
}

return M
