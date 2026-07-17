-- lua/flux/server_test.lua - Unit tests for flux.server.
-- <jed@nelson.ac> // 2026-06-13
--
-- The HTTP server itself requires live sockets and is not tested here.
-- This file covers the pure functions exported by the module.

local h = require("test.harness")
local server = require("flux.server")

--
-- Query string parsing
--

h.describe("query string parsing", function()
    h.it("parses a single key=value pair", function()
        local t = server.parse_qs("q=hello")
        h.expect(t.q).equals("hello")
    end)

    h.it("parses multiple pairs separated by ampersand", function()
        local t = server.parse_qs("a=1&b=2&c=3")
        h.expect(t.a).equals("1")
        h.expect(t.b).equals("2")
        h.expect(t.c).equals("3")
    end)

    h.it("decodes percent-encoded characters", function()
        local t = server.parse_qs("q=hello%20world")
        h.expect(t.q).equals("hello world")
    end)

    h.it("decodes plus sign as space", function()
        local t = server.parse_qs("q=hello+world")
        h.expect(t.q).equals("hello world")
    end)

    h.it("decodes mixed percent-encoding and plus", function()
        local t = server.parse_qs("q=Navier%2DStokes+equations")
        h.expect(t.q).equals("Navier-Stokes equations")
    end)

    h.it("key with no value gets an empty string", function()
        local t = server.parse_qs("flag=")
        h.expect(t.flag).equals("")
    end)

    h.it("returns an empty table for an empty string", function()
        local t = server.parse_qs("")
        h.expect(next(t)).is_nil()
    end)

    h.it("returns an empty table for nil input", function()
        local t = server.parse_qs(nil)
        h.expect(next(t)).is_nil()
    end)

    h.it("decodes percent-encoded key names", function()
        local t = server.parse_qs("my%20key=value")
        h.expect(t["my key"]).equals("value")
    end)
end)
