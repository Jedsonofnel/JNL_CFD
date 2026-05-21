geo2d = require("jnl.geo2d")
shapes = geo2d.shapes
domain = geo2d.domain
ui = require("jnl.ui")

local outer = shapes.rect(-1, -1, 1, 1)
local hole = shapes.circle(0, 0, 0.3, 64)

local d = domain.new(outer)
local ok, err = d:add_hole(hole, 2)
if not ok then
	error("domain error: " .. err)
end

local g = d:build()
ui.display_pslg(g)
