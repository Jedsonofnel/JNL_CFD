-- ui/init.lua - initialisation for UI helpers in lua
-- <jed@nelson.ac> // 2026-05-21

local ui_internal = require("jnl.ui_internal")

local M = {}

M._doc = "UI facade for displaying PSLGs and meshes"

M._doc_subsection = {
	"Use display_pslg and display_mesh for normal interactive work; they use the module default window.",
	"The default window is focused before display and replaced automatically if it has gone stale.",
	"Use spawn when managing multiple windows explicitly. Explicit handles are not silently replaced by display helpers.",
	"Use close(handle) or close() to close a window and clear the module default when appropriate.",
}

local default_ui = nil

--
-- Internal helpers
--

local function handle_closed(handle)
	if not handle then
		return true
	end

	return handle:closed()
end

local function clear_default_if(handle)
	if handle and handle == default_ui then
		default_ui = nil
	end
end

local function fresh_default()
	default_ui = ui_internal.spawn()
	return default_ui
end

local function try_display(handle, send)
	if handle_closed(handle) then
		return false
	end

	if not handle:focus() then
		return false
	end

	return send(handle)
end

local function display_with_recovery(handle, send)
	local h = handle or M.default()

	if try_display(h, send) then
		return true
	end

	if handle then
		return false
	end

	clear_default_if(h)

	h = fresh_default()
	return try_display(h, send)
end

--
-- Public API
--

function M.spawn()
	local h = ui_internal.spawn()
	if not default_ui or handle_closed(default_ui) then
		default_ui = h
	end

	return h
end

function M.default()
	if handle_closed(default_ui) then
		return fresh_default()
	end

	return default_ui
end

function M.display_pslg(g, handle)
	return display_with_recovery(handle, function(h)
		return h:send_pslg(g)
	end)
end

function M.display_mesh(mesh, handle)
	return display_with_recovery(handle, function(h)
		return h:send_mesh(mesh)
	end)
end

function M.close(handle)
	local h = handle or default_ui
	if not h then
		return
	end

	h:close()
	clear_default_if(h)
end

--
-- API
--

M._api = {
	spawn = {
		args = "",
		ret = "UIHandle",
		doc = "Spawn a new UI window; first call also sets the module default",
	},
	default = {
		args = "",
		ret = "UIHandle",
		doc = "Return the default window, spawning one if none exists or if it has gone stale",
	},
	display_pslg = {
		args = "g:PSLG, handle:UIHandle?",
		ret = "bool",
		doc = "Send a PSLG to the given window or default; focuses first and recovers a stale default once",
	},
	display_mesh = {
		args = "mesh:Mesh, handle:UIHandle?",
		ret = "bool",
		doc = "Send a mesh to the given window or default; focuses first and recovers a stale default once",
	},
	close = {
		args = "handle:UIHandle?",
		ret = "nil",
		doc = "Close the given window, or the default, and clear the default if it matches",
	},
}

M._types = {
	UIHandle = {
		kind = "userdata",
		constructor = "jnl.ui.spawn",
		doc = "Handle to a JNLCFD visualiser window",
		methods = {
			closed = {
				args = "",
				ret = "bool",
				doc = "Return true if the UI window has been closed or the handle is stale",
			},
			focus = {
				args = "",
				ret = "bool",
				doc = "Focus the UI window; returns false if the handle is stale",
			},
			send_pslg = {
				args = "g:PSLG",
				ret = "bool",
				doc = "Send a PSLG to this UI window",
			},
			send_mesh = {
				args = "mesh:Mesh",
				ret = "bool",
				doc = "Send a mesh to this UI window",
			},
			close = {
				args = "",
				ret = "nil",
				doc = "Close this UI window and invalidate the Lua handle",
			},
		},
	},
}

return M
