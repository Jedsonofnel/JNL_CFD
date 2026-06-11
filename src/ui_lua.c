#include "lua_bindings.h"
#include "ui.h"
#include "geo2d/domain2d.h"

#define UI_MT "jnl.ui"

static jnl_ui_handle *check_ui(lua_State *L, int idx)
{
	jnl_ui_handle **hp = luaL_checkudata(L, idx, UI_MT);
	if (!*hp)
		luaL_error(L, "closed jnl.ui handle");
	return *hp;
}

//
// Lifecycle
//

static int l_ui_spawn(lua_State *L)
{
	jnl_ui_handle **h = lua_newuserdata(L, sizeof(jnl_ui_handle *));
	*h = NULL;
	luaL_setmetatable(L, UI_MT);
	*h = jnl_ui_spawn();
	if (!*h)
		return luaL_error(L, "jnl_ui_spawn failed");
	return 1;
}

static int l_ui_closed(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	lua_pushboolean(L, jnl_ui_closed(h));
	return 1;
}

static int l_ui_focus(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	lua_pushboolean(L, jnl_ui_focus(h) == 0);
	return 1;
}

static int l_ui_close(lua_State *L)
{
	jnl_ui_handle **hp = luaL_checkudata(L, 1, UI_MT);
	if (*hp) {
		jnl_ui_free(*hp);
		*hp = NULL;
	}
	return 0;
}

static int l_ui_gc(lua_State *L)
{
	jnl_ui_handle **hp = luaL_checkudata(L, 1, UI_MT);
	if (*hp) {
		jnl_ui_free(*hp);
		*hp = NULL;
	}
	return 0;
}

static int l_ui_tostring(lua_State *L)
{
	jnl_ui_handle **hp = luaL_checkudata(L, 1, UI_MT);
	if (*hp)
		lua_pushfstring(L, "jnl.ui: handle %p", (void *)*hp);
	else
		lua_pushstring(L, "jnl.ui: (closed)");
	return 1;
}

//
// Geometry
//

static int l_ui_send_domain(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	struct jnl_domain2d *d =
	    *(struct jnl_domain2d **)luaL_checkudata(L, 2, DOMAIN2D_MT);
	lua_pushboolean(L, jnl_ui_send_domain(h, d) == 0);
	return 1;
}

static int l_ui_send_mesh(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_pushboolean(L, jnl_ui_send_mesh(h, m) == 0);
	return 1;
}

//
// Live field updates
//

static int l_ui_set_field(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	const char *name = luaL_checkstring(L, 2);
	lua_vec *v = check_vec(L, 3);
	lua_pushboolean(L, jnl_ui_set_field(h, name, v->data, (u32)v->len) == 0);
	return 1;
}

static int l_ui_set_vector(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	const char *name = luaL_checkstring(L, 2);
	const char *fx = luaL_checkstring(L, 3);
	const char *fy = luaL_checkstring(L, 4);
	lua_pushboolean(L, jnl_ui_set_vector(h, name, fx, fy) == 0);
	return 1;
}

static int l_ui_view_field(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	// nil or "" both mean wireframe
	const char *name = lua_isnoneornil(L, 2) ? "" : luaL_checkstring(L, 2);
	lua_pushboolean(L, jnl_ui_view_field(h, name) == 0);
	return 1;
}

static int l_ui_view_mesh(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	// default true if arg omitted
	bool show = lua_isnoneornil(L, 2) ? true : lua_toboolean(L, 2);
	lua_pushboolean(L, jnl_ui_view_mesh(h, show) == 0);
	return 1;
}

//
// Registration
//

static const luaL_Reg ui_methods[] = {
    {"closed", l_ui_closed},         {"send_domain", l_ui_send_domain},
    {"send_mesh", l_ui_send_mesh},   {"set_field", l_ui_set_field},
    {"set_vector", l_ui_set_vector}, {"view_field", l_ui_view_field},
    {"view_mesh", l_ui_view_mesh},   {"focus", l_ui_focus},
    {"close", l_ui_close},           {"__gc", l_ui_gc},
    {"__tostring", l_ui_tostring},   {NULL, NULL}};

static const luaL_Reg ui_funcs[] = {{"spawn", l_ui_spawn}, {NULL, NULL}};

int luaopen_ui_internal(lua_State *L)
{
	luaL_newmetatable(L, UI_MT);
	luaL_setfuncs(L, ui_methods, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, ui_funcs);
	return 1;
}
