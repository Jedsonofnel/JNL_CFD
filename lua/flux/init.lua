-- lua/flux/init.lua - Flux web framework entry point.
-- <jed@nelson.ac> // 2026-06-13

--- Minimal web framework for the JNL documentation server.
---
--- Exposes the HTML DSL, request router, and HTTP server as sub-modules.
--- Typical usage:
---
---   local flux   = require "flux"
---   local router = flux.router.new()
---   local H      = flux.html
---
---   local _ENV = H.env()
---
---   router:get("/", function(req, res)
---     res.html(html { body { h1 "JNLCFD" } })
---   end)
---
---   flux.serve(router, { port = 8080 })
local M  = {}

M.html   = require "flux.html"
M.router = require "flux.router"
M.server = require "flux.server"

--- Convenience alias for flux.server.serve.
---@param router FluxRouter
---@param opts? table
function M.serve(router, opts)
	M.server.serve(router, opts)
end

return M
