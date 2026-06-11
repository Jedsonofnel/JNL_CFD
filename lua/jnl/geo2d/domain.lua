-- geo2d/domain.lua
-- <jed@nelson.ac> // 2026-06-10

local opt = require("jnl.core.optional")
local I = opt.require("jnl.domain2d_internal")

--- Construct meshable Domain2D objects from closed Pen shapes.
---
--- The primary entry point is from_pen(), which converts a tagged Pen into a
--- Domain2D and a MarkerRegistry.  Holes and interior regions are added to
--- the Domain2D afterwards:
---
---     local curve  = require("jnl.geo2d.curve")
---     local d, reg = domain.from_pen(p)
---
---     -- Add a circular hole; seed must be a point strictly inside the hole.
---     local hole = curve.circle({0.5, 0.5}, 0.1)
---     d:add_hole("cylinder", reg:get("cylinder"), hole, {0.5, 0.5})
local M = {}

--
-- Marker registry
--

---@class MarkerRegistry
---@field next integer
---@field map  table<string, integer>
local Registry = {}
Registry.__index = Registry

---@param name string
---@return integer
function Registry:get(name)
	if not self.map[name] then
		self.map[name] = self.next
		self.next = self.next + 1
	end
	return self.map[name]
end

local function new_registry()
	return setmetatable({ next = 1, map = {} }, Registry)
end

--
-- Constructors
--

---@class Domain2DOpts
---@field default string?  Default BC name for untagged outer segments (default: "wall").

---Construct a `Domain2D` from a closed `Pen`.
---@param  p    Pen
---@param  opts Domain2DOpts?
---@return Domain2D, MarkerRegistry
function M.from_pen(p, opts)
	opts = opts or {}
	local reg = new_registry()
	local default = opts.default or "wall"
	local outer = p:build()
	local d = I.new(outer)
	d:set_default_marker(reg:get(default))

	-- Iterate segs (not tags) so we preserve order and pick up hints.
	-- Tags are unique so there's no double-registration risk.
	local hints = {}
	for _, seg in ipairs(p.segs) do
		if seg.tag then
			d:add_patch(seg.tag, reg:get(seg.tag), seg.curve)
			if seg.hint then
				hints[seg.tag] = seg.hint
			end
		end
	end

	-- Attached for the PSLG lowering step (geo2d/domain2d_pslg commit).
	d.reg = reg
	d.hints = hints
	return d, reg
end

return M
