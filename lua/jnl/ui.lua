-- lua/jnl/ui.lua - Lua wrapper around jnl.ui_internal (C)
-- <jed@nelson.ac> // 2026-05-21

local opt = require("jnl.core.optional")
local I = opt.require("jnl.ui_internal")
local M = {}

--
-- Types
--

---@class jnl.ui.Handle
---Opaque C userdata.  All methods return false/nil on a closed handle.
---@field closed    fun(self: jnl.ui.Handle): boolean
---@field send_domain fun(self: jnl.ui.Handle, domain: Domain2D): boolean
---@field send_mesh   fun(self: jnl.ui.Handle, mesh: Mesh2D): boolean
---@field set_field   fun(self: jnl.ui.Handle, name: string, data: VecUD): boolean
---@field set_vector  fun(self: jnl.ui.Handle, name: string, fx: string, fy: string): boolean
---@field view_field  fun(self: jnl.ui.Handle, name?: string): boolean   -- nil/"" = wireframe
---@field view_mesh   fun(self: jnl.ui.Handle, show?: boolean): boolean
---@field focus       fun(self: jnl.ui.Handle): boolean
---@field close       fun(self: jnl.ui.Handle)

--
--  Module state
--

---@type jnl.ui.Handle|nil
local default_ui = nil

--
-- Internal helpers
--

---@param handle jnl.ui.Handle|nil
---@return boolean
local function handle_closed(handle)
	if not handle then return true end
	return handle:closed()
end

---@param handle jnl.ui.Handle|nil
local function clear_default_if(handle)
	if handle and handle == default_ui then
		default_ui = nil
	end
end

---@return jnl.ui.Handle
local function fresh_default()
	default_ui = I.spawn()
	return default_ui
end

-- Try one send; focus first so the window comes to the front.
---@param handle jnl.ui.Handle
---@param send   fun(h: jnl.ui.Handle): boolean
---@return boolean
local function try_display(handle, send)
	if handle_closed(handle) then return false end
	if not handle:focus() then return false end
	return send(handle)
end

-- For setup-time display calls (domain, mesh): if the handle is dead and no
-- explicit handle was given, spawn a new default and retry once.
-- For live field updates we do NOT recover — the caller must check closed().
---@param handle jnl.ui.Handle|nil  explicit handle, or nil to use default
---@param send   fun(h: jnl.ui.Handle): boolean
---@return boolean
local function display_with_recovery(handle, send)
	local h = handle or M.default()
	if try_display(h, send) then return true end
	-- Only recover for the implicit default — explicit handles are the
	-- caller's responsibility.
	if handle then return false end
	clear_default_if(h)
	h = fresh_default()
	return try_display(h, send)
end

--
-- Public API
--

--- Spawn a new visualiser window.  The first call also sets it as the default.
---@return jnl.ui.Handle
function M.spawn()
	local h = I.spawn()
	if not default_ui or handle_closed(default_ui) then
		default_ui = h
	end
	return h
end

--- Return (or lazily spawn) the process-wide default handle.
---@return jnl.ui.Handle
function M.default()
	if not default_ui or default_ui:closed() then
		return fresh_default()
	end
	return default_ui
end

--- Send a domain2d object for boundary display.
--- Spawns a new default window if the current one is dead.
---@param domain  Domain2D
---@param handle? jnl.ui.Handle
---@return boolean
function M.display_domain(domain, handle)
	return display_with_recovery(handle, function(h)
		return h:send_domain(domain)
	end)
end

--- Send mesh topology.
--- Spawns a new default window if the current one is dead.
---@param mesh    Mesh2D
---@param handle? jnl.ui.Handle
---@return boolean
function M.display_mesh(mesh, handle)
	return display_with_recovery(handle, function(h)
		return h:send_mesh(mesh)
	end)
end

--- Push a scalar field update.  No recovery — call during a live solve loop
--- after display_mesh has already succeeded.  Returns false silently if the
--- window has been closed (e.g. user dismissed it mid-run).
---@param name    string    field name, e.g. "p" or "U_x"
---@param data    VecUD   values; length must match mesh vertex or cell count
---@param handle? jnl.ui.Handle
---@return boolean
function M.set_field(name, data, handle)
	local h = handle or default_ui
	if not h or h:closed() then return false end
	return h:set_field(name, data)
end

--- Associate two scalar fields as a named vector (for magnitude rendering).
---@param name    string          e.g. "U"
---@param fx      string          e.g. "U_x"
---@param fy      string          e.g. "U_y"
---@param handle? jnl.ui.Handle
---@return boolean
function M.set_vector(name, fx, fy, handle)
	local h = handle or default_ui
	if not h or h:closed() then return false end
	return h:set_vector(name, fx, fy)
end

--- Switch the active field overlay.  Pass nil or "" for wireframe-only.
---@param name?   string          field or vector name; nil = wireframe
---@param handle? jnl.ui.Handle
---@return boolean
function M.view_field(name, handle)
	local h = handle or default_ui
	if not h or h:closed() then return false end
	return h:view_field(name)
end

--- Show or hide the mesh wireframe overlay.
---@param show?   boolean         default true
---@param handle? jnl.ui.Handle
---@return boolean
function M.view_mesh(show, handle)
	local h = handle or default_ui
	if not h or h:closed() then return false end
	return h:view_mesh(show)
end

--- Close the given handle (or the default), removing it from the default slot.
---@param handle? jnl.ui.Handle
function M.close(handle)
	local h = handle or default_ui
	if not h then return end
	h:close()
	clear_default_if(h)
end

return M
