#include "lua_bindings.h"
#include "ui.h"

#define UI_MT "jnl.ui"

static jnl_ui_handle *check_ui(lua_State *L, int idx)
{
	return *(jnl_ui_handle **)luaL_checkudata(L, idx, UI_MT);
}

static int l_ui_spawn(lua_State *L)
{
	jnl_ui_handle **h = lua_newuserdata(L, sizeof(jnl_ui_handle *));
	*h = jnl_ui_spawn();
	luaL_setmetatable(L, UI_MT);
	return 1;
}

static int l_ui_send_pslg(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	struct jnl_pslg *g = luaL_checkudata(L, 2, "jnl.pslg");
	lua_pushboolean(L, jnl_ui_send_pslg(h, g) == 0);
	return 1;
}

static int l_ui_send_mesh(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	struct jnl_mesh *m = luaL_checkudata(L, 2, "jnl.mesh");
	lua_pushboolean(L, jnl_ui_send_mesh(h, m) == 0);
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
	jnl_ui_handle *h = check_ui(L, 1);
	jnl_ui_close(h);
	return 0;
}

static int l_ui_gc(lua_State *L)
{
	jnl_ui_handle *h = check_ui(L, 1);
	jnl_ui_close(h);
	jnl_ui_free(h);
	return 0;
}

static int l_ui_tostring(lua_State *L)
{
	lua_pushstring(L, "jnl_ui_handle");
	return 1;
}

static const luaL_Reg ui_methods[] = {{"send_pslg", l_ui_send_pslg},
                                      {"send_mesh", l_ui_send_mesh},
                                      {"focus", l_ui_focus},
                                      {"close", l_ui_close},
                                      {"__gc", l_ui_gc},
                                      {"__tostring", l_ui_tostring},
                                      {NULL, NULL}};

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
