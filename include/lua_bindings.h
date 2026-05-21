#ifndef JNL_LUA_BINDINGS_H
#define JNL_LUA_BINDINGS_H

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

int luaopen_geo2d_internal(lua_State *L);
int luaopen_mesh2d_internal(lua_State *L);
int luaopen_ui_internal(lua_State *L);

// bit of a smell but small enough that it's fine
static inline void register_preloaders(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");

	lua_pushcfunction(L, luaopen_geo2d_internal);
	lua_setfield(L, -2, "jnl.geo2d_internal");

	lua_pushcfunction(L, luaopen_ui_internal);
	lua_setfield(L, -2, "jnl.ui_internal");

	lua_pushcfunction(L, luaopen_mesh2d_internal);
	lua_setfield(L, -2, "jnl.mesh2d_internal");

	lua_pop(L, 2);
}

#endif
