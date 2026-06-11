-- showcase/demo_circle_domain.lua - Flow-around-a-circle domain preview
-- <jed@nelson.ac> // 2026-06-11

local pen    = require("jnl.geo2d.pen")
local domain = require("jnl.geo2d.domain")
local curve  = require("jnl.geo2d.curve")
local ui     = require("jnl.ui")

-- Geometry
local L, H   = 4.0, 2.0 -- channel length and height
local cx, cy = 1.5, 1.0 -- cylinder centre
local r      = 0.25     -- cylinder radius

local function build_domain()
	local p = pen.new()
		:at(0, 0)
		:north(H):tag("inlet")
		:east(L):tag("top")
		:south(H):tag("outlet")
		:close():tag("bottom")

	local d, reg = domain.from_pen(p)

	local cyl = curve.circle({ cx, cy }, r)
	d:add_hole("cylinder", reg:get("cylinder"), cyl, { cx, cy })

	return d
end

function show()
	ui.display_domain(build_domain())
end

show()
print("Circle-flow domain loaded.  Call (show) to re-display.")
return show
