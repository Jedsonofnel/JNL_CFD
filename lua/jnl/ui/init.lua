-- ui/init.lua - initialisation for UI helpers in lua
-- <jed@nelson.ac> // 2026-05-21

local ui_internal = require("jnl.ui_internal")

local M = {}

M._doc = "UI window facade: spawn and manage visualiser windows for PSLGs and meshes"
M._api = {
	spawn        = { args = "", ret = "UIHandle", doc = "Spawn a new UI window; first call also sets the module default" },
	default      = { args = "", ret = "UIHandle", doc = "Return the default window, spawning one if none exists" },
	display_pslg = { args = "g:PSLG, handle:UIHandle?", ret = "bool", doc = "Send a PSLG to the given window (or default); focuses window first" },
	display_mesh = { args = "mesh:Mesh, handle:UIHandle?", ret = "bool", doc = "Send a mesh to the given window (or default); focuses window first" },
	close        = { args = "handle:UIHandle?", ret = "nil", doc = "Close the given window (or default) and clear the default if it matches" },
}

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
	return h:focus() and h:send_pslg(g)
end

function M.display_mesh(mesh, handle)
	local h = handle or M.default()
	return h:focus() and h:send_mesh(mesh)
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
