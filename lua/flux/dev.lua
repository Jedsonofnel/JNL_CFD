-- lua/flux/dev.lua - Development utilities for the Flux web framework.
-- <jed@nelson.ac> // 2026-06-13

--- Dev-mode helpers: live reload and asset cache busting.
---
---   local dev = require("flux").dev
---
---   if dev.enabled then dev.add_route(router) end
---
---   -- In layout:
---   H.link { rel="stylesheet", href="/assets/base.css" .. dev.v },
---   when(dev.enabled, dev.livereload_script()),
---
--- Activated by setting JNL_DEV=1 in the environment.
local M = {}

M.enabled = os.getenv("JNL_DEV") == "1"
M.boot_time = tostring(os.time())

--- Cache-busting query suffix. "?v=<timestamp>" in dev, "" in production.
M.v = M.enabled and ("?v=" .. M.boot_time) or ""

--- Register the /__livereload endpoint on router.
--- Returns the server's boot timestamp as plain text.
--- The browser script polls this and reloads when it changes.
---@param router FluxRouter
function M.add_route(router)
    local boot = M.boot_time
    router:get("/__livereload", function(_, res)
        res.json(boot)
        return true
    end)
end

--- Inline <script> that polls /__livereload and reloads on change.
---@return string
function M.livereload_script()
    return [[<script>
(function () {
	var last = null;
	setInterval(function () {
		fetch("/__livereload")
			.then(function (r) { return r.text(); })
			.then(function (t) {
				if (last !== null && last !== t) { location.reload(); }
				last = t;
			})
			.catch(function () {});
	}, 800);
})();
</script>]]
end

return M
