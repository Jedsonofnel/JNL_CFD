-- web/main.lua - documentation site main entrypoint
-- <jed@nelson.ac> // 2026-06-13

local flux = require "flux"
local router = flux.router.new()
local H = flux.html
local dev = flux.dev
local _ENV = H.env()
local script_dir = arg[0]:match("(.+)/[^/]+$") or "."

--
-- Layout
--

local function layout(content)
	return doctype .. H.html { lang = "en" } {
		H.head {
			H.meta { charset = "UTF-8" },
			H.meta { name = "viewport", content = "width=device-width, initial-scale=1" },
			H.title "JNLCFD",
			H.link { rel = "stylesheet", href = "/assets/base.css" .. dev.v },
			H.link { rel = "stylesheet", href = "/assets/components.css" .. dev.v },
			when(dev.enabled, raw(dev.livereload_script())),
		},
		H.body {
			{ content }
		},
	}
end

--
-- Routes
--

if dev.enabled then dev.add_route(router) end

router:get("/", function(_, res)
	res.html(layout {
		header { h1 "Welcome to JNLCFD" },
		main {
			p [[A lightweight, scriptable CFD code built for rapid problem
			    exploration and reproducible, auditable workflows.]],
			p [[Another paragraph]]
		}
	})
end)

--
-- Start
--

flux.serve(router, {
	port        = 8080,
	static      = "/assets/",
	static_root = script_dir .. "/assets",
})
