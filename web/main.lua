-- web/main.lua - documentation site main entrypoint
-- <jed@nelson.ac> // 2026-06-13

local flux = require("flux")
local router = flux.router.new()
local dev = flux.dev
local script_dir = arg[0]:match("(.+)/[^/]+$") or "."

local H = flux.html
local _ENV = H.env()

--
-- Layout
--

local function layout(page)
	local doc   = { html = page.content, meta = page.meta, toc = page.toc }
	local split = flux.md.split_h1(doc)
	local title = split.meta.title or split.title or "JNLCFD"

	return doctype .. H.html { lang = "en" } {
		H.head {
			H.meta { charset = "UTF-8" },
			H.meta { name = "viewport", content = "width=device-width, initial-scale=1" },
			H.title(title),
			H.link { rel = "stylesheet", href = "/assets/base.css" .. dev.v },
			H.link { rel = "stylesheet", href = "/assets/components.css" .. dev.v },
			when(dev.enabled, raw(dev.livereload_script())),
		},
		H.body {
			H.header { H.h1(split.title or title) },
			H.main {
				H.nav {
					a { href = "/" } "Home",
					when(#split.toc > 0, function()
						return H.map(split.toc, function(entry)
							return H.div { style = "padding-left:" .. (entry.level - 1) .. "em" } {
								H.a { href = "#" .. entry.id } (entry.text)
							}
						end)
					end)
				},
				H.raw(split.html),
			},
		},
	}
end

local function layout_content(content)
	local page = { content = H.render(content), meta = {}, toc = {} }
	return layout(page)
end

--
-- Routes
--

if dev.enabled then dev.add_route(router) end

router:get("/", function(_, res)
	res.html(layout_content {
		h1 "Welcome to JNLCFD",

		p [[A lightweight, scriptable CFD code built for rapid problem
			    exploration and reproducible, auditable workflows.]],

		p [[Another paragraph]],

		a { href = "docs/algorithm" } "Algorithm documentation",
	})
end)

router:static("/assets", script_dir .. "/assets")

router:mount("/docs", script_dir .. "/docs", {
	layout = layout,
})

--
-- Start
--

flux.serve(router, {
	port = 8080,
})
