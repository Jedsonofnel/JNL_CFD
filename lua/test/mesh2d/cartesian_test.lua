-- test/mesh2d/cartesian_test.lua - tests for jnl.mesh2d.cartesian
-- <jed@nelson.ac> // 2026-06-12

local h    = require("test.harness")
local cart = require("jnl.mesh2d.cartesian")

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-9)
end

h.describe("cartesian.build: basic return", function()
	h.it("returns a mesh for valid inputs", function()
		local mesh, err = cart.build(1, 1, 4, 4)
		h.expect(mesh).is_not_nil(err)
		h.expect(err).is_nil()
	end)
end)

h.describe("cartesian.build: cell topology", function()
	h.it("cell count equals nx * ny", function()
		local mesh = cart.build(1, 1, 6, 8)
		h.expect(mesh:n_cells()).equals(48)
	end)

	h.it("non-square nx ny are both respected", function()
		local mesh = cart.build(3, 2, 12, 5)
		h.expect(mesh:n_cells()).equals(60)
	end)

	h.it("internal face count is nx*(ny-1) + ny*(nx-1)", function()
		-- 4x4 cells: horizontal internal = 4*3 = 12, vertical = 3*4 = 12, total = 24
		local mesh = cart.build(1, 1, 4, 4)
		h.expect(mesh:n_internal_faces()).equals(24)
	end)

	h.it("boundary face count is 2*(nx + ny)", function()
		-- 6x4 cells: 2*(6+4) = 20
		local mesh = cart.build(1, 1, 6, 4)
		h.expect(mesh:n_boundary_faces()).equals(20)
	end)
end)

h.describe("cartesian.build: patches", function()
	h.it("has four patches", function()
		local mesh = cart.build(1, 1, 4, 4)
		h.expect(mesh:n_patches()).equals(4)
	end)

	h.it("patch names are north east south west", function()
		local mesh  = cart.build(1, 1, 4, 4)
		local names = {}
		for _, p in ipairs(mesh:patches()) do
			names[p.name] = true
		end
		h.expect(names["north"]).is_truthy()
		h.expect(names["east"]).is_truthy()
		h.expect(names["south"]).is_truthy()
		h.expect(names["west"]).is_truthy()
	end)

	h.it("south patch has nx faces", function()
		local mesh = cart.build(1, 1, 6, 4)
		h.expect(mesh:patch_by_name("south").n_faces).equals(6)
	end)

	h.it("north patch has nx faces", function()
		local mesh = cart.build(1, 1, 6, 4)
		h.expect(mesh:patch_by_name("north").n_faces).equals(6)
	end)

	h.it("west patch has ny faces", function()
		local mesh = cart.build(1, 1, 6, 4)
		h.expect(mesh:patch_by_name("west").n_faces).equals(4)
	end)

	h.it("east patch has ny faces", function()
		local mesh = cart.build(1, 1, 6, 4)
		h.expect(mesh:patch_by_name("east").n_faces).equals(4)
	end)

	h.it("patch_by_name returns a table with expected fields", function()
		local p = cart.build(1, 1, 4, 4):patch_by_name("south")
		h.expect(p).is_not_nil()
		h.expect(p.name).equals("south")
		h.expect(p.n_faces > 0).is_truthy()
	end)

	h.it("patch_by_name returns nil for an unknown name", function()
		h.expect(cart.build(1, 1, 4, 4):patch_by_name("inlet")).is_nil()
	end)
end)

h.describe("cartesian.build: geometry", function()
	h.it("mean cell size is approximately sqrt(area / n_cells)", function()
		local w, ht, nx, ny = 2, 3, 4, 6
		local mesh          = cart.build(w, ht, nx, ny)
		local expected      = math.sqrt(w * ht / (nx * ny))
		h.expect(near(mesh:mean_cell_size(), expected, 0.01)).is_truthy()
	end)

	h.it("all cell centres are strictly inside the domain", function()
		local w, ht = 2.0, 3.0
		local mesh  = cart.build(w, ht, 4, 6)
		for i = 1, mesh:n_cells() do
			local x, y = mesh:cell_centre(i)
			h.expect(x > 0 and x < w).is_truthy()
			h.expect(y > 0 and y < ht).is_truthy()
		end
	end)

	h.it("all cell volumes are positive", function()
		local mesh = cart.build(1, 1, 4, 4)
		for i = 1, mesh:n_cells() do
			h.expect(mesh:cell_vol(i) > 0).is_truthy()
		end
	end)

	h.it("sum of cell volumes equals total domain area", function()
		local w, ht = 3, 2
		local mesh  = cart.build(w, ht, 6, 4)
		local total = 0
		for i = 1, mesh:n_cells() do
			total = total + mesh:cell_vol(i)
		end
		h.expect(near(total, w * ht, 1e-10)).is_truthy()
	end)
end)
