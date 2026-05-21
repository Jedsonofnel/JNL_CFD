#include "lua_bindings.h"

static int l_geo2d_test(lua_State *L)
{
	printf("geo2d_test() called from C!\n");
	lua_pushstring(L, "hello from C");
	return 1;
}

static const luaL_Reg geo2d_internal_funcs[] = {
    {"geo2d_test", l_geo2d_test},
    {NULL, NULL},
};

int luaopen_geo2d_internal(lua_State *L)
{
	luaL_newlib(L, geo2d_internal_funcs);
	return 1;
}
