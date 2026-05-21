#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

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

	if (argc > 1) {
		const char *script = argv[1];
		const char *ext = strrchr(script, '.');
		if (!ext || strcmp(ext, ".lua") != 0) {
			fprintf(stderr, "Error: script must be a .lua file\n");
			lua_close(L);
			return 1;
		}

		if (luaL_dofile(L, script) != LUA_OK) {
			fprintf(stderr, "Error running script: %s\n", lua_tostring(L, -1));
			lua_close(L);
			return 1;
		}

		lua_pushstring(L, script);
		lua_setglobal(L, "_script");
	}

	if (luaL_dofile(L, repl_path) != LUA_OK) {
		fprintf(stderr, "Error: %s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

	lua_close(L);

	return EXIT_SUCCESS;
}
