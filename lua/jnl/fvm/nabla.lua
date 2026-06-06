-- jnl/fvm/nabla.lua
local nb = require("jnl.nabla")
local G  = require("jnl.core.glyphs")

nb.register_accessor("diag", {
	dep_type = nb.DEP_MATRIX,
	field    = true,
	rank     = function(r) return r end,
	pretty   = function(node)
		return "diag(" .. (node.a and node.a.name or "?") .. ")"
	end,
})

nb.register_accessor("prev", {
	dep_type = nb.DEP_TEMPORAL,
	field    = true,
	rank     = function(r) return r end,
	pretty   = function(node)
		return (node.a and node.a.name or "?") .. (G.prev or "⁻")
	end,
})

nb.register_accessor("expl", {
	dep_type = nb.DEP_LAGGED,
	field    = true,
	rank     = function(r) return r end,
	pretty   = function(node)
		return (node.a and node.a.name or "?") .. (G.expl or "ˡ")
	end,
})

return nb
