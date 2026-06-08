-- jnl/fvm/nabla.lua
local nb = require("jnl.nabla")
local G  = require("jnl.core.glyphs")

nb.register_accessor("diag", {
	field  = true,
	rank   = function(a) return a.rank end,
	pretty = function(node)
		return "diag(" .. (node.a and node.a.name or "?") .. ")"
	end,
})

nb.register_accessor("prev", {
	field  = true,
	rank   = function(a) return a.rank end,
	pretty = function(node)
		return (node.a and node.a.name or "?") .. (G.prev or "⁻")
	end,
})

nb.register_accessor("expl", {
	field  = true,
	rank   = function(a) return a.rank end,
	pretty = function(node)
		return (node.a and node.a.name or "?") .. (G.expl or "ˡ")
	end,
})

nb.register_accessor("mwi", {
	binary = true,
	rank   = function(a, b)
		assert(a.rank == 1,
			"mwi: first argument '" .. (a.name or "?") .. "' must be a vector (rank 1)")
		assert(b.rank == 0,
			"mwi: second argument '" .. (b.name or "?") .. "' must be a scalar (rank 0)")
		return 1
	end,
	pretty = function(node)
		return "mwi(" .. (node.a.name or "?") .. "," .. (node.b.name or "?") .. ")"
	end,
})

return nb
