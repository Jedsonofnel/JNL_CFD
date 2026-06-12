-- test/mesh2d/block_test.lua - tests for jnl.mesh2d.block
-- <jed@nelson.ac> // 2026-06-12

local h     = require("test.harness")
local blk   = require("jnl.mesh2d.block")
local curve = require("jnl.geo2d.curve")
local pen   = require("jnl.geo2d.pen")
local E     = require("jnl.mesh2d.edges")

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-9)
end

local WALL   = 1
local INLET  = 2
local OUTLET = 3
local TOP    = 4

-- Points-to-cells: a block with ni x nj grid points has (ni-1)*(nj-1) cells.
local function cells(ni, nj) return (ni - 1) * (nj - 1) end

-- Correctly-oriented boundary curves for a unit square [0,1]x[0,1].
-- Each curve's k=0 end sits at the corner closer to the origin:
--   south: SW(0,0) -> SE(1,0),  east: SE(1,0) -> NE(1,1)
--   north: NW(0,1) -> NE(1,1),  west: SW(0,0) -> NW(0,1)
local function sq_south() return curve.line(0, 0, 1, 0) end
local function sq_east() return curve.line(1, 0, 1, 1) end
local function sq_north() return curve.line(0, 1, 1, 1) end
local function sq_west() return curve.line(0, 0, 0, 1) end

-- A complete, valid unit square block builder.
local function unit_block(ni, nj)
	return blk.block(ni, nj)
		:south(sq_south(), { marker = WALL })
		:east(sq_east(), { marker = OUTLET })
		:north(sq_north(), { marker = TOP })
		:west(sq_west(), { marker = INLET })
		:tfi()
end

--
-- BlockBuilder: validation
--

h.describe("BlockBuilder: missing edges", function()
	h.it("missing south returns nil and an error string", function()
		local mesh, err = blk.block(5, 5)
			:east(sq_east(), { marker = OUTLET })
			:north(sq_north(), { marker = TOP })
			:west(sq_west(), { marker = INLET })
			:tfi()
			:build()
		h.expect(mesh).is_nil()
		h.expect(err).is_not_nil()
	end)

	h.it("error message names the missing edge", function()
		local _, err = blk.block(5, 5)
			:east(sq_east())
			:north(sq_north())
			:west(sq_west())
			:build()
		h.expect(err:find("south")).is_truthy()
	end)

	h.it("no edges set returns nil", function()
		local mesh, err = blk.block(5, 5):tfi():build()
		h.expect(mesh).is_nil()
		h.expect(err).is_not_nil()
	end)
end)

--
-- BlockBuilder: successful builds
--

h.describe("BlockBuilder: single block", function()
	h.it("unit square builds without error", function()
		local mesh, err = unit_block(5, 5):build()
		h.expect(mesh).is_not_nil(err)
	end)

	h.it("cell count is (ni-1)*(nj-1)", function()
		local mesh = unit_block(7, 9):build()
		h.expect(mesh:n_cells()).equals(cells(7, 9))
	end)

	h.it("all cell volumes are positive", function()
		local mesh = unit_block(5, 5):build()
		for i = 1, mesh:n_cells() do
			h.expect(mesh:cell_vol(i) > 0).is_truthy()
		end
	end)

	h.it("sum of cell volumes equals block area", function()
		local mesh  = unit_block(9, 9):build()
		local total = 0
		for i = 1, mesh:n_cells() do
			total = total + mesh:cell_vol(i)
		end
		h.expect(near(total, 1.0, 1e-10)).is_truthy()
	end)

	h.it("smooth after tfi produces a mesh", function()
		-- Curved east edge gives the smoother something to improve.
		-- Arc centred at (1, 0.5) r=0.5: starts at (1,0), ends at (1,1),
		-- bulges outward to (1.5, 0.5).
		local mesh, err = blk.block(9, 9)
			:south(sq_south(), { marker = WALL })
			:east(curve.arc(1, 0.5, 0.5, -math.pi / 2, math.pi / 2),
				{ marker = OUTLET })
			:north(sq_north(), { marker = TOP })
			:west(sq_west(), { marker = INLET })
			:tfi()
			:smooth({ max_iter = 10, omega = 1.0 })
			:build()
		h.expect(mesh).is_not_nil(err)
		h.expect(mesh:n_cells()).equals(cells(9, 9))
	end)
end)

--
-- BlockBuilder: from_pen
--

h.describe("BlockBuilder: from_pen", function()
	-- A CW trace of the unit square gives correctly-oriented south and east
	-- edges (k=0 at the near-origin corner).  North and west come out reversed
	-- and must be passed through :reversed() when used as block edges.
	local function cw_unit_pen()
		return pen.new()
			:at(0, 0)
			:east(1):tag("s") -- south: (0,0)->(1,0)  correct orientation
			:north(1):tag("e") -- east:  (1,0)->(1,1)  correct orientation
			:west(1):tag("n") -- north: (1,1)->(0,1)  reversed
			:close():tag("w") -- west:  (0,1)->(0,0)  reversed
	end

	h.it("from_pen assigns specified edges", function()
		local p = cw_unit_pen()
		local mesh, err = blk.block(9, 9)
			:from_pen(p, { south = "s", east = "e" },
				{ south = WALL, east = OUTLET })
			:north(p:get("n"):reversed(), { marker = TOP })
			:west(p:get("w"):reversed(), { marker = INLET })
			:tfi()
			:build()
		h.expect(mesh).is_not_nil(err)
		h.expect(mesh:n_cells()).equals(cells(9, 9))
	end)

	h.it("from_pen unknown edge name throws", function()
		local p = cw_unit_pen()
		h.expect(function()
			blk.block(5, 5):from_pen(p, { bad_edge = "s" })
		end).throws("from_pen")
	end)

	h.it("from_pen unknown pen tag throws", function()
		local p = cw_unit_pen()
		h.expect(function()
			blk.block(5, 5):from_pen(p, { south = "no_such_tag" })
		end).throws()
	end)
end)

--
-- GridBuilder: validation
--

h.describe("GridBuilder: edge validation", function()
	h.it("assigned join-target edge returns error", function()
		local g  = blk.grid()
		local b0 = g:block(5, 5)
		local b1 = g:block(5, 5)
		g:join(b0, E.E, b1, E.W)

		b0:south(sq_south()):east(sq_east()):north(sq_north()):west(sq_west()):tfi()
		-- b1 assigns west even though it is a join target
		b1:south(curve.line(1, 0, 2, 0), { marker = WALL })
			:east(curve.line(2, 0, 2, 1), { marker = OUTLET })
			:north(curve.line(1, 1, 2, 1), { marker = TOP })
			:west(curve.line(1, 0, 1, 1)) -- must not be assigned
			:tfi()

		local mesh, err = g:build()
		h.expect(mesh).is_nil()
		h.expect(err).is_not_nil()
	end)

	h.it("ni/nj mismatch on joined edges returns error", function()
		local g  = blk.grid()
		local b0 = g:block(5, 5) -- east edge has nj=5 points
		local b1 = g:block(5, 7) -- west edge has nj=7 points: mismatch
		g:join(b0, E.E, b1, E.W)

		b0:south(sq_south(), { marker = WALL })
			:east(sq_east())
			:north(sq_north(), { marker = TOP })
			:west(sq_west(), { marker = INLET })
			:tfi()

		b1:south(curve.line(1, 0, 2, 0), { marker = WALL })
			:east(curve.line(2, 0, 2, 1), { marker = OUTLET })
			:north(curve.line(1, 1, 2, 1), { marker = TOP })
			:tfi()

		local mesh, err = g:build()
		h.expect(mesh).is_nil()
		h.expect(err).is_not_nil()
	end)

	h.it("corner mismatch returns error", function()
		local g  = blk.grid()
		local b0 = g:block(5, 5)
		local b1 = g:block(5, 5)
		g:join(b0, E.E, b1, E.W)

		b0:south(sq_south(), { marker = WALL })
			:east(sq_east())
			:north(sq_north(), { marker = TOP })
			:west(sq_west(), { marker = INLET })
			:tfi()

		-- b1 south starts at x=1.1 instead of x=1: SW corner mismatches b0 east start.
		b1:south(curve.line(1.1, 0, 2.1, 0), { marker = WALL })
			:east(curve.line(2.1, 0, 2.1, 1), { marker = OUTLET })
			:north(curve.line(1.1, 1, 2.1, 1), { marker = TOP })
			:tfi()

		local mesh, err = g:build()
		h.expect(mesh).is_nil()
		h.expect(err).is_not_nil()
	end)

	h.it("corner mismatch error message mentions 'join'", function()
		local g  = blk.grid()
		local b0 = g:block(5, 5)
		local b1 = g:block(5, 5)
		g:join(b0, E.E, b1, E.W)

		b0:south(sq_south()):east(sq_east()):north(sq_north()):west(sq_west()):tfi()
		b1:south(curve.line(1.1, 0, 2.1, 0))
			:east(curve.line(2.1, 0, 2.1, 1))
			:north(curve.line(1.1, 1, 2.1, 1))
			:tfi()

		local _, err = g:build()
		h.expect(err:find("join")).is_truthy()
	end)

	h.it("join_ring with fewer than two blocks throws", function()
		local g = blk.grid()
		local b = g:block(5, 5)
		h.expect(function()
			g:join_ring({ b }, E.E, E.W)
		end).throws()
	end)
end)

--
-- GridBuilder: two-block join
--

h.describe("GridBuilder: two-block join", function()
	-- Two unit squares joined east-to-west, forming a [0,2]x[0,1] rectangle.
	local function two_block(ni, nj)
		local g  = blk.grid()
		local b0 = g:block(ni, nj)
		local b1 = g:block(ni, nj)
		g:join(b0, E.E, b1, E.W)

		b0:south(curve.line(0, 0, 1, 0), { marker = WALL })
			:east(curve.line(1, 0, 1, 1))
			:north(curve.line(0, 1, 1, 1), { marker = TOP })
			:west(curve.line(0, 0, 0, 1), { marker = INLET })
			:tfi()

		b1:south(curve.line(1, 0, 2, 0), { marker = WALL })
			:east(curve.line(2, 0, 2, 1), { marker = OUTLET })
			:north(curve.line(1, 1, 2, 1), { marker = TOP })
			:tfi()

		return g:build()
	end

	h.it("builds without error", function()
		local mesh, err = two_block(5, 5)
		h.expect(mesh).is_not_nil(err)
	end)

	h.it("cell count is the sum of both blocks", function()
		local ni, nj = 5, 7
		local mesh = two_block(ni, nj)
		h.expect(mesh:n_cells()).equals(2 * cells(ni, nj))
	end)

	h.it("all cell volumes are positive", function()
		local mesh = two_block(5, 5)
		for i = 1, mesh:n_cells() do
			h.expect(mesh:cell_vol(i) > 0).is_truthy()
		end
	end)

	h.it("total cell volume equals combined block area", function()
		local mesh  = two_block(5, 5)
		local total = 0
		for i = 1, mesh:n_cells() do
			total = total + mesh:cell_vol(i)
		end
		-- Two unit squares: area = 2.0
		h.expect(near(total, 2.0, 1e-10)).is_truthy()
	end)
end)

--
-- GridBuilder: join_ring (O-mesh)
--

h.describe("GridBuilder: join_ring O-mesh", function()
	-- Four-block O-mesh: annulus between r_in=1 and r_out=3, four 90-degree sectors.
	-- join_ring connects b[i].E -> b[i+1].W cyclically.
	local function o_mesh(nt, nr)
		local PI    = math.pi
		local r_in  = 1.0
		local r_out = 3.0

		local g     = blk.grid()
		local bs    = {
			g:block(nt, nr), g:block(nt, nr),
			g:block(nt, nr), g:block(nt, nr),
		}
		g:join_ring(bs, E.E, E.W)

		for i = 0, 3 do
			local t0 = i * PI / 2
			local t1 = (i + 1) * PI / 2
			bs[i + 1]
				:south(curve.arc(0, 0, r_in, t0, t1), { marker = WALL })
				:north(curve.arc(0, 0, r_out, t0, t1), { marker = OUTLET })
				:east(curve.line(
					r_in * math.cos(t1), r_in * math.sin(t1),
					r_out * math.cos(t1), r_out * math.sin(t1)))
				:tfi()
		end

		return g:build()
	end

	h.it("builds without error", function()
		local mesh, err = o_mesh(9, 5)
		h.expect(mesh).is_not_nil(err)
	end)

	h.it("cell count is 4 * (nt-1) * (nr-1)", function()
		local nt, nr = 9, 5
		local mesh   = o_mesh(nt, nr)
		h.expect(mesh:n_cells()).equals(4 * cells(nt, nr))
	end)

	h.it("all cell volumes are positive", function()
		local mesh = o_mesh(9, 5)
		for i = 1, mesh:n_cells() do
			h.expect(mesh:cell_vol(i) > 0).is_truthy()
		end
	end)

	h.it("total cell volume is close to annulus area", function()
		-- TFI approximates arc boundaries with sampled polylines.
		-- Area error decreases with mesh refinement; ~0.7% is expected for nt=9.
		local PI    = math.pi
		local r_in  = 1.0
		local r_out = 3.0
		local mesh  = o_mesh(9, 5)
		local total = 0
		for i = 1, mesh:n_cells() do
			total = total + mesh:cell_vol(i)
		end
		local expected = PI * (r_out * r_out - r_in * r_in)
		local rel_err  = math.abs(total - expected) / expected
		h.expect(rel_err < 0.02).is_truthy()
	end)
end)
