-- ui/init.lua - initialisation for UI helpers in lua
-- <jed@nelson.ac> // 2026-05-21

local ui_internal = require("ui_internal")

local M = {}

local default_ui = nil

function M.spawn()
	local h = ui_internal.spawn()
	if not default_ui then
		default_ui = h
	end
	return h
end

function M.default()
	if not default_ui then
		default_ui = ui_internal.spawn()
	end
	return default_ui
end

function M.display_pslg(g, handle)
	local h = handle or M.default()
	return h:send_pslg(g)
end

function M.display_mesh(mesh, handle)
	local h = handle or M.default()
	return h:send_mesh(mesh)
end

function M.close(handle)
	local h = handle or default_ui
	if h then
		h:close()
		if h == default_ui then
			default_ui = nil
		end
	end
end

return M
