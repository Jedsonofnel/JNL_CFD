-- jnl/mesh2d/block.lua - structured block and multi-block grid builders
-- <jed@nelson.ac> // 2026-06-12

--- Fluent builders for single structured blocks and multi-block grids.
---
--- Single block:
---
---     local mesh2d = require("jnl.mesh2d")
---     local mesh, err = mesh2d.block(33, 33)
---         :south(curve.line(0,0, 1,0), { marker = WALL })
---         :east( curve.line(1,0, 1,1), { marker = OUTLET })
---         :north(curve.line(0,1, 1,1), { marker = TOP })
---         :west( curve.line(0,0, 0,1), { marker = INLET })
---         :tfi()
---         :build()
---
--- Multi-block grid:
---
---     local E  = mesh2d.edges
---     local g  = mesh2d.grid()
---     local b0 = g:block(33, 33)
---     local b1 = g:block(33, 33)
---     g:join(b0, E.E, b1, E.W)
---     b0:south(...):east(...):north(...):west(...)
---     b1:south(...):east(...):north(...)   -- west is auto-populated
---     local mesh, err = g:build()
---
--- O-mesh cyclic topology:
---
---     local blocks = { g:block(33,33), g:block(33,33), g:block(33,33), g:block(33,33) }
---     g:join_ring(blocks, E.E, E.W)
local M = {}

local opt = require("jnl.core.optional")
local S = opt.require("jnl.strucmesh2d_internal")
local C = require("jnl.geo2d.curve")

local EDGE_NAME = {
	[S.SOUTH] = "south",
	[S.EAST]  = "east",
	[S.NORTH] = "north",
	[S.WEST]  = "west",
}

local EDGE_CONST = {
	south = S.SOUTH,
	east  = S.EAST,
	north = S.NORTH,
	west  = S.WEST,
}

local ALL_EDGES = { S.SOUTH, S.EAST, S.NORTH, S.WEST }

--
-- Internal helpers
--

---@class BlockEdgeSpec
---@field curve  Curve2D
---@field dist   Dist1D
---@field marker integer?

local function set_edge(self, edge, c, opts)
	opts = opts or {}
	self.edges[edge] = {
		curve  = c,
		dist   = opts.dist or C.uniform(),
		marker = opts.marker,
	}
	return self
end

-- Sample all edges that are not join targets onto a raw block.
local function apply_free_edges(raw_blk, edges, skip)
	for edge, spec in pairs(edges) do
		if not skip[edge] then
			if spec.marker then raw_blk:set_edge_marker(edge, spec.marker) end
			raw_blk:sample_edge(edge, spec.curve, spec.dist)
		end
	end
end

-- Validate one block: every edge is either user-assigned or a join target,
-- and no edge is both.
local function check_block_edges(h, idx, targets)
	for _, edge in ipairs(ALL_EDGES) do
		local assigned = h.edges[edge] ~= nil
		local targeted = targets[edge] ~= nil

		if not assigned and not targeted then
			return ("block %d: edge '%s' is neither assigned nor a join target")
				:format(idx, EDGE_NAME[edge])
		end

		if assigned and targeted then
			return ("block %d: edge '%s' is a join target and must not be assigned "
					.. "(the grid will populate it via copy_edge)")
				:format(idx, EDGE_NAME[edge])
		end
	end
end

-- Collect join targets: { [handle] = { [edge] = true } }.
local function collect_join_targets(joins)
	local targets = {}
	for _, j in ipairs(joins) do
		local t = targets[j.dst] or {}
		t[j.dst_edge] = true
		targets[j.dst] = t
	end
	return targets
end

local CORNER_ADJ = {
	[S.SOUTH] = {
		{ adj = S.WEST, pt = "start" },
		{ adj = S.EAST, pt = "start" },
	},
	[S.EAST] = {
		{ adj = S.SOUTH, pt = "finish" },
		{ adj = S.NORTH, pt = "finish" },
	},
	[S.NORTH] = {
		{ adj = S.WEST, pt = "finish" },
		{ adj = S.EAST, pt = "finish" },
	},
	[S.WEST] = {
		{ adj = S.SOUTH, pt = "start" },
		{ adj = S.NORTH, pt = "start" },
	},
}

local function curve_pt(spec, which)
	local p = spec.curve[which](spec.curve)
	return p[1], p[2]
end

local function check_corners(joins, tol)
	tol = tol or 1e-10
	local tol2 = tol * tol

	for ji, j in ipairs(joins) do
		local src_spec = j.src.edges[j.src_edge]
		if not src_spec then
			-- Already caught by check_block_edges; just skip.
			return
		end

		local corners = CORNER_ADJ[j.dst_edge]
		if not corners then return end

		for ci = 1, 2 do
			local corn     = corners[ci]
			local dst_spec = j.dst.edges[corn.adj]

			-- Skip if the adjacent destination edge is also a join target
			-- (no free curve to read the corner from).
			if dst_spec then
				-- ci=1 is dst k=0; ci=2 is dst k=last.
				-- reversed swaps which src endpoint maps to which dst corner.
				local src_which
				if ci == 1 then
					src_which = j.reversed and "finish" or "start"
				else
					src_which = j.reversed and "start" or "finish"
				end

				local sx, sy = curve_pt(src_spec, src_which)
				local dx, dy = curve_pt(dst_spec, corn.pt)
				local ex, ey = sx - dx, sy - dy

				if ex * ex + ey * ey > tol2 then
					return ("join %d: corner mismatch — "
							.. "block %d edge '%s' endpoint does not meet "
							.. "block %d edge '%s' (gap %.3g, tol %.3g)")
						:format(ji,
							j.src.idx, EDGE_NAME[j.src_edge],
							j.dst.idx, EDGE_NAME[corn.adj],
							math.sqrt(ex * ex + ey * ey), tol)
				end
			end
		end
	end
end

--
-- BlockBuilder
--

---@class BlockBuilder
---@field private ni     integer
---@field private nj     integer
---@field private edges  table<integer, BlockEdgeSpec>
---@field private do_tfi boolean
---@field private smooth_opts table?
local BlockBuilder = {}
BlockBuilder.__index = BlockBuilder

--- Create a standalone structured block builder.
---
--- ni is the number of grid points along the south and north edges.
--- nj is the number of grid points along the east and west edges.
---@param ni integer
---@param nj integer
---@return BlockBuilder
function M.block(ni, nj)
	return setmetatable({
		ni     = ni,
		nj     = nj,
		edges  = {},
		do_tfi = false,
		smooth = nil,
	}, BlockBuilder)
end

--- Lower the block to a Mesh2D.
---@return Mesh2D? mesh
---@return string?  err
function BlockBuilder:build()
	for _, edge in ipairs(ALL_EDGES) do
		if not self.edges[edge] then
			return nil, ("block: edge '%s' not defined"):format(EDGE_NAME[edge])
		end
	end

	local blk = S.block_new(self.ni, self.nj)
	apply_free_edges(blk, self.edges, {})

	-- tfi() and smooth() raise Lua errors on failure; let them propagate.
	if self.do_tfi then blk:tfi() end
	if self.smooth_opts then blk:smooth(self.smooth_opts) end

	return blk:build()
end

---@return Domain2D?, string?
function BlockBuilder:to_domain()
	for _, edge in ipairs(ALL_EDGES) do
		if not self.edges[edge] then
			return nil, ("block: edge '%s' not defined"):format(EDGE_NAME[edge])
		end
	end

	local blk = S.block_new(self.ni, self.nj)
	apply_free_edges(blk, self.edges, {})

	if self.do_tfi then blk:tfi() end
	if self.smooth_opts then blk:smooth(self.smooth_opts) end

	return blk:to_domain()
end

-- Returns the number of grid points on a given edge of a block handle.
local function edge_npoints(h, edge)
	if edge == S.SOUTH or edge == S.NORTH then return h.ni end
	return h.nj
end

-- Validate that every join's two edges have matching point counts.
-- Runs before any C allocation so mismatches produce a clean error.
local function check_join_npoints(joins)
	for i, j in ipairs(joins) do
		local n_src = edge_npoints(j.src, j.src_edge)
		local n_dst = edge_npoints(j.dst, j.dst_edge)
		if n_src ~= n_dst then
			return ("join %d: point count mismatch — "
					.. "block %d edge '%s' has %d points, "
					.. "block %d edge '%s' has %d points")
				:format(i,
					j.src.idx, EDGE_NAME[j.src_edge], n_src,
					j.dst.idx, EDGE_NAME[j.dst_edge], n_dst)
		end
	end
end

--
-- GridBlockHandle
--

--- A block handle returned by GridBuilder:block().
---
--- Has the same fluent edge-assignment API as BlockBuilder.  The handle
--- stores intent; GridBuilder:build() performs materialisation in the
--- correct order.
---@class GridBlockHandle
---@field ni     integer
---@field nj     integer
---@field edges  table<integer, BlockEdgeSpec>
---@field do_tfi boolean
---@field smooth_opts table?
---@field idx integer  1-based position in the grid's block list.
---@field raw Block?   Raw block set by GridBuilder:build().
local GridBlockHandle = {}
GridBlockHandle.__index = GridBlockHandle

--
-- BlockBuilder methods
--

--- Set the south (j = 0) edge.
---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return BlockBuilder
function BlockBuilder:south(c, opts) return set_edge(self, S.SOUTH, c, opts) end

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return BlockBuilder
function BlockBuilder:east(c, opts) return set_edge(self, S.EAST, c, opts) end

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return BlockBuilder
function BlockBuilder:north(c, opts) return set_edge(self, S.NORTH, c, opts) end

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return BlockBuilder
function BlockBuilder:west(c, opts) return set_edge(self, S.WEST, c, opts) end

--- Set an edge by direction constant.
---@param edge  integer Direction constant (E.S / E.E / E.N / E.W).
---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return BlockBuilder
function BlockBuilder:edge(edge, c, opts) return set_edge(self, edge, c, opts) end

--- Populate edges from a Pen's tagged segments.
---@param p       Pen
---@param mapping table<string, string>
---@param markers table<string, integer>?
---@return BlockBuilder
function BlockBuilder:from_pen(p, mapping, markers)
	markers = markers or {}
	for edge_name, tag in pairs(mapping) do
		local e = assert(EDGE_CONST[edge_name],
			("from_pen: unknown edge name '%s'"):format(edge_name))
		set_edge(self, e, p:get(tag), {
			dist   = C.uniform(),
			marker = markers[edge_name],
		})
	end
	return self
end

---@return BlockBuilder
function BlockBuilder:tfi()
	self.do_tfi = true
	return self
end

---@param opts? { max_iter:integer?, omega:number?, tol:number? }
---@return BlockBuilder
function BlockBuilder:smooth(opts)
	self.smooth_opts = opts or {}
	return self
end

--
-- GridBlockHandle methods (identical bodies, different return annotations)
--

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return GridBlockHandle
function GridBlockHandle:south(c, opts) return set_edge(self, S.SOUTH, c, opts) end

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return GridBlockHandle
function GridBlockHandle:east(c, opts) return set_edge(self, S.EAST, c, opts) end

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return GridBlockHandle
function GridBlockHandle:north(c, opts) return set_edge(self, S.NORTH, c, opts) end

---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return GridBlockHandle
function GridBlockHandle:west(c, opts) return set_edge(self, S.WEST, c, opts) end

---@param edge  integer
---@param c     Curve2D
---@param opts? { marker:integer?, dist:Dist1D? }
---@return GridBlockHandle
function GridBlockHandle:edge(edge, c, opts) return set_edge(self, edge, c, opts) end

---@param p       Pen
---@param mapping table<string, string>
---@param markers table<string, integer>?
---@return GridBlockHandle
function GridBlockHandle:from_pen(p, mapping, markers)
	markers = markers or {}
	for edge_name, tag in pairs(mapping) do
		local e = assert(EDGE_CONST[edge_name],
			("from_pen: unknown edge name '%s'"):format(edge_name))
		set_edge(self, e, p:get(tag), {
			dist   = C.uniform(),
			marker = markers[edge_name],
		})
	end
	return self
end

---@return GridBlockHandle
function GridBlockHandle:tfi()
	self.do_tfi = true
	return self
end

---@param opts? { max_iter:integer?, omega:number?, tol:number? }
---@return GridBlockHandle
function GridBlockHandle:smooth(opts)
	self.smooth_opts = opts or {}
	return self
end

--
-- GridBuilder
--

---@class GridJoin
---@field src      GridBlockHandle
---@field src_edge integer
---@field dst      GridBlockHandle
---@field dst_edge integer
---@field reversed boolean

---@class GridBuilder
---@field blocks GridBlockHandle[]
---@field joins  GridJoin[]
local GridBuilder = {}
GridBuilder.__index = GridBuilder

--- Create a multi-block structured grid builder.
---@return GridBuilder
function M.grid()
	return setmetatable({
		blocks = {},
		joins  = {},
	}, GridBuilder)
end

--- Add a block to the grid and return a handle for edge assignment.
---
--- tfi and smooth may be set immediately as shorthand:
---
---     local b = g:block(33, 33, { tfi = true, smooth = { max_iter = 100 } })
---@param ni    integer
---@param nj    integer
---@param opts? { tfi:boolean?, smooth:table? }
---@return GridBlockHandle
function GridBuilder:block(ni, nj, opts)
	opts = opts or {}
	local h = setmetatable({
		ni = ni,
		nj = nj,
		edges = {},
		do_tfi = opts.tfi or false,
		smooth_opts = opts.smooth,
		idx = #self.blocks + 1,
		raw = nil,
	}, GridBlockHandle)
	self.blocks[h.idx] = h
	return h
end

--- Declare a topology join between two block edges.
---
--- src_blk.src_edge must be assigned by the caller.
--- dst_blk.dst_edge must NOT be assigned; build() populates it via
--- copy_edge in declaration order before running TFI.
---
--- Multi-hop chains (A -> B -> C) work provided joins are declared in
--- propagation order.
---@param src_blk  GridBlockHandle
---@param src_edge integer
---@param dst_blk  GridBlockHandle
---@param dst_edge integer
---@param reversed boolean?
---@return GridBuilder self
function GridBuilder:join(src_blk, src_edge, dst_blk, dst_edge, reversed)
	self.joins[#self.joins + 1] = {
		src      = src_blk,
		src_edge = src_edge,
		dst      = dst_blk,
		dst_edge = dst_edge,
		reversed = reversed or false,
	}
	return self
end

--- Declare cyclic joins between a sequence of blocks.
---
--- Joins blocks[1].out_edge -> blocks[2].in_edge, ...,
---       blocks[n].out_edge -> blocks[1].in_edge.
---
--- Used for O-meshes and any topology that wraps around a full loop.
---@param blocks   GridBlockHandle[]
---@param out_edge integer  Source edge on each block (e.g. E.E).
---@param in_edge  integer  Destination edge on each block (e.g. E.W).
---@param reversed boolean?
---@return GridBuilder self
function GridBuilder:join_ring(blocks, out_edge, in_edge, reversed)
	local n = #blocks
	assert(n >= 2, "join_ring: need at least two blocks")
	for i = 1, n do
		self:join(blocks[i], out_edge, blocks[(i % n) + 1], in_edge, reversed)
	end
	return self
end

---@param self GridBuilder
---@return Grid?, table<integer, integer>?, string?
local function prepare_raw_grid(self)
	local join_targets = collect_join_targets(self.joins)

	for i, h in ipairs(self.blocks) do
		local targets = join_targets[h] or {}
		local err = check_block_edges(h, i, targets)
		if err then return nil, nil, err end
	end

	local corner_err = check_corners(self.joins)
	if corner_err then return nil, nil, corner_err end

	local npoints_err = check_join_npoints(self.joins)
	if npoints_err then return nil, nil, npoints_err end

	for _, h in ipairs(self.blocks) do
		local targets = join_targets[h] or {}
		h.raw = S.block_new(h.ni, h.nj)
		apply_free_edges(h.raw, h.edges, targets)
	end

	for _, j in ipairs(self.joins) do
		j.dst.raw:copy_edge(j.dst_edge, j.src.raw, j.src_edge, j.reversed)
	end

	for _, h in ipairs(self.blocks) do
		if h.do_tfi then h.raw:tfi() end
		if h.smooth_opts then h.raw:smooth(h.smooth_opts) end
	end

	local raw_grid = S.grid_new()
	local ids = {}
	for i, h in ipairs(self.blocks) do
		ids[i] = raw_grid:add_block(h.raw)
	end

	for _, j in ipairs(self.joins) do
		raw_grid:add_join(
			ids[j.src.idx], j.src_edge,
			ids[j.dst.idx], j.dst_edge,
			j.reversed
		)
	end

	return raw_grid, ids, nil
end

--- Build the grid into a single Mesh2D.
---@return Mesh2D? mesh
---@return string?  err
function GridBuilder:build()
	local raw_grid, _, err = prepare_raw_grid(self)
	if err then return nil, err end
	assert(raw_grid)

	local ok, check_err = raw_grid:check()
	if not ok then return nil, check_err end

	return raw_grid:build()
end

---@return Domain2D? domain
---@return string? err
function GridBuilder:to_domain()
	local raw_grid, _, err = prepare_raw_grid(self)
	if err then return nil, err end
	assert(raw_grid)

	return raw_grid:to_domain()
end

return M
