-- lua/flux/router_test.lua - Unit tests for flux.router.
-- <jed@nelson.ac> // 2026-06-13

local h = require "test.harness"
local router = require "flux.router"

local function req(method, path)
	return { method = method, path = path, params = {} }
end

--
-- Static routes
--

h.describe("static routes", function()
	h.it("exact path matches and calls handler", function()
		local r   = router.new()
		local hit = false
		r:get("/", function()
			hit = true; return true
		end)
		r:dispatch(req("GET", "/"), {})
		h.expect(hit).is_truthy()
	end)

	h.it("non-matching path does not call handler", function()
		local r   = router.new()
		local hit = false
		r:get("/foo", function()
			hit = true; return true
		end)
		r:dispatch(req("GET", "/bar"), {})
		h.expect(hit).is_falsy()
	end)

	h.it("method must match exactly", function()
		local r   = router.new()
		local hit = false
		r:get("/foo", function()
			hit = true; return true
		end)
		r:dispatch(req("POST", "/foo"), {})
		h.expect(hit).is_falsy()
	end)

	h.it("returns nil when no route matches", function()
		local r      = router.new()
		local result = r:dispatch(req("GET", "/missing"), {})
		h.expect(result).is_nil()
	end)

	h.it("returns nil on an empty router", function()
		local r      = router.new()
		local result = r:dispatch(req("GET", "/"), {})
		h.expect(result).is_nil()
	end)
end)

--
-- Parameterised routes
--

h.describe("parameterised routes", function()
	h.it("single param is captured into req.params", function()
		local r        = router.new()
		local captured = nil
		r:get("/guide/:slug", function(rq)
			captured = rq.params.slug
			return true
		end)
		r:dispatch(req("GET", "/guide/quickstart"), {})
		h.expect(captured).equals("quickstart")
	end)

	h.it("multiple params are all captured", function()
		local r   = router.new()
		local got = {}
		r:get("/api/:version/:resource", function(rq)
			got.version  = rq.params.version
			got.resource = rq.params.resource
			return true
		end)
		r:dispatch(req("GET", "/api/v1/mesh"), {})
		h.expect(got.version).equals("v1")
		h.expect(got.resource).equals("mesh")
	end)

	h.it("param does not match across slash boundaries", function()
		local r   = router.new()
		local hit = false
		r:get("/a/:x", function()
			hit = true; return true
		end)
		r:dispatch(req("GET", "/a/b/c"), {})
		h.expect(hit).is_falsy()
	end)

	h.it("params are empty on a static route match", function()
		local r   = router.new()
		local got = nil
		r:get("/static", function(rq)
			got = rq.params
			return true
		end)
		r:dispatch(req("GET", "/static"), {})
		h.expect(next(got)).is_nil()
	end)
end)

--
-- Method shorthands
--

h.describe("method shorthands", function()
	h.it("post registers a POST handler", function()
		local r   = router.new()
		local hit = false
		r:post("/search", function()
			hit = true; return true
		end)
		r:dispatch(req("POST", "/search"), {})
		h.expect(hit).is_truthy()
	end)

	h.it("put registers a PUT handler", function()
		local r   = router.new()
		local hit = false
		r:put("/item", function()
			hit = true; return true
		end)
		r:dispatch(req("PUT", "/item"), {})
		h.expect(hit).is_truthy()
	end)

	h.it("delete registers a DELETE handler", function()
		local r   = router.new()
		local hit = false
		r:delete("/item", function()
			hit = true; return true
		end)
		r:dispatch(req("DELETE", "/item"), {})
		h.expect(hit).is_truthy()
	end)

	h.it("patch registers a PATCH handler", function()
		local r   = router.new()
		local hit = false
		r:patch("/item", function()
			hit = true; return true
		end)
		r:dispatch(req("PATCH", "/item"), {})
		h.expect(hit).is_truthy()
	end)
end)

--
-- Dispatch ordering
--

h.describe("dispatch ordering", function()
	h.it("first registered matching route wins", function()
		local r     = router.new()
		local order = {}
		r:get("/x", function()
			order[#order + 1] = 1; return true
		end)
		r:get("/x", function()
			order[#order + 1] = 2; return true
		end)
		r:dispatch(req("GET", "/x"), {})
		h.expect(#order).equals(1)
		h.expect(order[1]).equals(1)
	end)

	h.it("static route beats param route when registered first", function()
		local r   = router.new()
		local hit = nil
		r:get("/guide/index", function()
			hit = "static"; return true
		end)
		r:get("/guide/:slug", function()
			hit = "param"; return true
		end)
		r:dispatch(req("GET", "/guide/index"), {})
		h.expect(hit).equals("static")
	end)

	h.it("param route matches when static route does not", function()
		local r   = router.new()
		local hit = nil
		r:get("/guide/index", function()
			hit = "static"; return true
		end)
		r:get("/guide/:slug", function()
			hit = "param"; return true
		end)
		r:dispatch(req("GET", "/guide/meshing"), {})
		h.expect(hit).equals("param")
	end)
end)

--
-- Chainable registration
--

h.describe("chainable registration", function()
	h.it("on returns the router for chaining", function()
		local r  = router.new()
		local r2 = r:on("GET", "/", function() return true end)
		h.expect(r2).equals(r)
	end)

	h.it("shorthand methods return the router for chaining", function()
		local r  = router.new()
		local r2 = r:get("/a", function() return true end)
			:post("/b", function() return true end)
			:delete("/c", function() return true end)
		h.expect(r2).equals(r)
	end)
end)
