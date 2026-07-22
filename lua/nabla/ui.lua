-- [nfnl] lua/nabla/ui.fnl
local opt = require("nabla.core.optional")
local internal = opt.require("nabla.strucmesh2d_internal")
local default_ui = nil
local function handle_closed_3f(handle)
  if not handle then
    return true
  else
    return handle:closed()
  end
end
local function clear_default_if_21(handle)
  if (handle and (handle == default_ui)) then
    default_ui = nil
    return nil
  else
    return nil
  end
end
local function fresh_default_21()
  default_ui = internal.spawn()
  return default_ui
end
local function default_21()
  if (not default_ui or default_ui:closed()) then
    return fresh_default_21()
  else
    return default_ui
  end
end
local function try_display(handle, send)
  if (handle_closed_3f(handle) or not handle:focus()) then
    return false
  else
    return send(handle)
  end
end
local function display_with_recovery_21(_3fhandle, send)
  local h = (_3fhandle or default_21())
  if try_display(h, send) then
    return true
  elseif _3fhandle() then
    return false
  else
    clear_default_if_21(h)
    return try_display(fresh_default_21(), send)
  end
end
local function spawn_21()
  local h = internal.spawn()
  if (not default_ui or handle_closed_3f(default_ui)) then
    default_ui = h
  else
  end
  return h
end
local function display_mesh(mesh, _3fhandle)
  local function _7_(_241)
    return _241["send-mesh"](_241, mesh)
  end
  return display_with_recovery_21(_3fhandle, _7_)
end
local function set_field_21(name, data, _3fhandle)
  local h = (_3fhandle or default_ui)
  if (not h or h:closed()) then
    return false
  else
    return h:set_field(name, data)
  end
end
local function set_vector_21(name, fx, fy, _3fhandle)
  local h = (_3fhandle or default_ui)
  if (not h or h:closed()) then
    return false
  else
    return h:set_vector(name, fx, fy)
  end
end
local function view_field(name, _3fhandle)
  local h = (_3fhandle or default_ui)
  if (not h or h:closed()) then
    return false
  else
    return h:view_field(name)
  end
end
local function view_mesh(show_3f, _3fhandle)
  local h = (_3fhandle or default_ui)
  if (not h or h:closed()) then
    return false
  else
    return h:view_mesh(show_3f)
  end
end
local function close_21(_3fhandle)
  local h = (_3fhandle or default_ui)
  if h then
    h:close()
    return clear_default_if_21(h)
  else
    return nil
  end
end
return {["default!"] = default_21, ["spawn!"] = spawn_21, ["display-mesh"] = display_mesh, ["set-field!"] = set_field_21, ["set-vector!"] = set_vector_21, ["view-field"] = view_field, ["view-mesh"] = view_mesh, ["close!"] = close_21}
