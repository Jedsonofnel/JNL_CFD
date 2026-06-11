-- test/geo2d/pen_test.lua
local h   = require("test.harness")
local pen = require("jnl.geo2d.pen")

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-9)
end

h.describe("pen construction", function()
	h.it(":at() sets the start position", function()
		local x, y = pen.new():at(3, 5):pos()
		h.expect(x).equals(3); h.expect(y).equals(5)
	end)

	h.it(":at() cannot be called twice", function()
		h.expect(function() pen.new():at(0, 0):at(1, 1) end).throws()
	end)

	h.it("movement before :at() errors", function()
		h.expect(function() pen.new():north(1) end).throws()
	end)

	h.it(":pos() before :at() errors", function()
		h.expect(function() pen.new():pos() end).throws()
	end)
end)

h.describe("pen line movement", function()
	h.it(":north() moves in +y", function()
		local x, y = pen.new():at(0, 0):north(5):pos()
		h.expect(near(x, 0, 1e-9)).is_truthy()
		h.expect(near(y, 5)).is_truthy()
	end)

	h.it(":east() moves in +x", function()
		local x, y = pen.new():at(0, 0):east(3):pos()
		h.expect(near(x, 3)).is_truthy()
		h.expect(near(y, 0, 1e-9)).is_truthy()
	end)

	h.it(":south() moves in -y", function()
		local _, y = pen.new():at(0, 2):south(2):pos()
		h.expect(near(y, 0)).is_truthy()
	end)

	h.it(":west() moves in -x", function()
		local x, _ = pen.new():at(4, 0):west(4):pos()
		h.expect(near(x, 0)).is_truthy()
	end)

	h.it(":line_to() updates position", function()
		local x, y = pen.new():at(0, 0):line_to(3, 4):pos()
		h.expect(near(x, 3)).is_truthy()
		h.expect(near(y, 4)).is_truthy()
	end)

	h.it(":line_to() degenerate target errors", function()
		h.expect(function() pen.new():at(1, 1):line_to(1, 1) end).throws()
	end)

	h.it(":bear() at 45° moves equally in x and y", function()
		local d    = math.sqrt(2)
		local x, y = pen.new():at(0, 0):bear(45, d):pos()
		h.expect(near(x, 1, 1e-6)).is_truthy()
		h.expect(near(y, 1, 1e-6)).is_truthy()
	end)
end)

h.describe("pen close", function()
	h.it(":close() returns pen to start position", function()
		local x, y = pen.new():at(0, 0):east(1):north(1):close():pos()
		h.expect(near(x, 0)).is_truthy()
		h.expect(near(y, 0)).is_truthy()
	end)

	h.it("movement after :close() errors", function()
		local p = pen.new():at(0, 0):east(1):close()
		h.expect(function() p:east(1) end).throws()
	end)

	h.it(":close() twice errors", function()
		local p = pen.new():at(0, 0):east(1):close()
		h.expect(function() p:close() end).throws()
	end)

	h.it(":close() from start adds no segment when already at start", function()
		-- Move and return exactly, then close: degenerate close adds no segment.
		local p = pen.new():at(0, 0):east(1):west(1):close()
		h.expect(#p.segs).equals(2) -- east + west, no closing segment
	end)
end)

h.describe("pen tagging", function()
	h.it(":tag() stores the curve in pen.tags", function()
		local p = pen.new():at(0, 0):east(1):tag("bottom")
		h.expect(p.tags["bottom"]).is_not_nil()
	end)

	h.it(":get() returns a curve with the correct length", function()
		local c = pen.new():at(0, 0):east(2):tag("bottom"):get("bottom")
		h.expect(near(c:length(), 2)).is_truthy()
	end)

	h.it("duplicate tag names error", function()
		local p = pen.new():at(0, 0):east(1):tag("a")
		h.expect(function() p:north(1):tag("a") end).throws()
	end)

	h.it(":tag() with no segments errors", function()
		h.expect(function() pen.new():at(0, 0):tag("x") end).throws()
	end)

	h.it(":get() unknown name errors", function()
		h.expect(function() pen.new():at(0, 0):east(1):get("nope") end).throws()
	end)

	h.it(":tag() returns self for chaining", function()
		local p = pen.new():at(0, 0):east(1):tag("a"):north(1)
		local _, y = p:pos()
		h.expect(near(y, 1)).is_truthy()
	end)
end)

h.describe("pen hints", function()
	h.it(":hint() stores opts on the most recent segment", function()
		local p = pen.new():at(0, 0):east(1):tag("bottom"):hint({ n = 32 })
		h.expect(p.segs[1].hint).is_not_nil()
		h.expect(p.segs[1].hint.n).equals(32)
	end)

	h.it(":hint() returns self for chaining", function()
		local p = pen.new():at(0, 0):east(1):tag("a"):hint({ n = 8 }):north(1)
		local _, y = p:pos()
		h.expect(near(y, 1)).is_truthy()
	end)

	h.it(":hint() with no segments errors", function()
		h.expect(function() pen.new():at(0, 0):hint({ n = 4 }) end).throws()
	end)

	h.it("hint is nil when not set", function()
		local p = pen.new():at(0, 0):east(1):tag("bottom")
		h.expect(p.segs[1].hint).is_nil()
	end)

	h.it("hint does not affect adjacent segments", function()
		local p = pen.new():at(0, 0)
			:east(1):tag("a"):hint({ n = 64 })
			:north(1):tag("b")
		h.expect(p.segs[1].hint).is_not_nil()
		h.expect(p.segs[2].hint).is_nil()
	end)
end)

h.describe("pen build", function()
	h.it("single segment produces a line", function()
		h.expect(pen.new():at(0, 0):east(1):build():kind()).equals("line")
	end)

	h.it("multiple segments produce a chain", function()
		h.expect(pen.new():at(0, 0):east(1):north(1):build():kind()).equals("chain")
	end)

	h.it("chain length matches sum of moves", function()
		local c = pen.new():at(0, 0):east(3):north(4):build()
		h.expect(near(c:length(), 7)).is_truthy()
	end)

	h.it("build with no segments errors", function()
		h.expect(function() pen.new():at(0, 0):build() end).throws()
	end)

	h.it("built curve start matches pen start", function()
		local s = pen.new():at(1, 2):east(3):build():start()
		h.expect(near(s[1], 1)).is_truthy()
		h.expect(near(s[2], 2)).is_truthy()
	end)
end)

h.describe("pen arc movement", function()
	h.it(":arc_turn() moves the position", function()
		local p    = pen.new():at(0, 0):arc_turn(90, 1)
		local x, y = p:pos()
		h.expect(math.sqrt(x * x + y * y) > 0.1).is_truthy("position should have moved")
	end)

	h.it(":arc_turn() zero radius errors", function()
		h.expect(function() pen.new():at(0, 0):arc_turn(90, 0) end).throws()
	end)

	h.it(":arc_turn() zero delta errors", function()
		h.expect(function() pen.new():at(0, 0):arc_turn(0, 1) end).throws()
	end)

	h.it(":arc_to() degenerate target errors", function()
		h.expect(function() pen.new():at(1, 1):arc_to(1, 1, 1) end).throws()
	end)

	h.it(":arc_to() radius too small errors", function()
		h.expect(function() pen.new():at(0, 0):arc_to(10, 0, 0.1) end).throws()
	end)

	h.it(":arc_to() moves to the target point", function()
		local x, y = pen.new():at(0, 0):arc_to(1, 0, 1):pos()
		h.expect(near(x, 1, 1e-6)).is_truthy()
		h.expect(near(y, 0, 1e-6)).is_truthy()
	end)
end)
