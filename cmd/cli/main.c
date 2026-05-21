#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

#include "lua_bindings.h"

#ifndef LUA_ASSET_PATH
#define LUA_ASSET_PATH "../lua" // fallback default
#endif

static void set_lua_path(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_pushstring(L, LUA_ASSET_PATH "/?.lua;" LUA_ASSET_PATH "/?/init.lua");
	lua_setfield(L, -2, "path");
	lua_pop(L, 1);
}

static void register_preloaders(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, luaopen_geo2d_internal);
	lua_setfield(L, -2, "geo2d_internal");
	lua_pop(L, 2);
}

int main(int argc, char **argv)
{
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);

	set_lua_path(L);
	register_preloaders(L);

	const char *repl_path = LUA_ASSET_PATH "/jnl/repl.lua";

	if (luaL_dofile(L, repl_path) != LUA_OK) {
		fprintf(stderr, "Error: %s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

	lua_close(L);

	return EXIT_SUCCESS;
}
