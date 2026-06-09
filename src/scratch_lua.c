#include "lua_bindings.h"
#include "scratch.h"

//
// Methods
//

static int l_pool_tostring(lua_State *L)
{
	struct jnl_scratch_pool *p = check_pool(L, 1);
	i32 in_use = 0;
	for (i32 i = 0; i < p->n_buf; i++)
		if (p->in_use[i])
			in_use++;
	lua_pushfstring(L, "scratch_pool(len=%d, n=%d, in_use=%d)", p->len,
	                p->n_buf, in_use);
	return 1;
}

static int l_pool_reset(lua_State *L)
{
	jnl_scratch_reset(check_pool(L, 1));
	return 0;
}

static int l_pool_depth(lua_State *L)
{
	struct jnl_scratch_pool *p = check_pool(L, 1);
	lua_pushinteger(L, p->n_buf);
	return 1;
}

static int l_pool_len(lua_State *L)
{
	lua_pushinteger(L, check_pool(L, 1)->len);
	return 1;
}

//
// Registration
//

static const luaL_Reg pool_mt[] = {{"reset", l_pool_reset},
                                   {"depth", l_pool_depth},
                                   {"len", l_pool_len},
                                   {"__tostring", l_pool_tostring},
                                   {NULL, NULL}};

int luaopen_scratch_internal(lua_State *L)
{
	luaL_newmetatable(L, POOL_MT);
	luaL_setfuncs(L, pool_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	lua_newtable(L);
	return 1;
}
