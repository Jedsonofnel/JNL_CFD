#include "lua_bindings.h"
#include "scratch.h"

/*
 * Constructor
 */

static int l_pool_new(lua_State *L)
{
	i32 n = (i32)luaL_checkinteger(L, 1);
	luaL_argcheck(L, n > 0, 1, "pool length must be positive");
	struct jnl_scratch_pool **pp = lua_newuserdata(L, sizeof(void *));
	*pp = jnl_scratch_pool_new(n);
	if (!*pp)
		return luaL_error(L, "scratch_pool allocation failed");
	luaL_setmetatable(L, POOL_MT);
	return 1;
}

/*
 * Methods
 */

static int l_pool_gc(lua_State *L)
{
	struct jnl_scratch_pool *p = check_pool(L, 1);
	if (p)
		jnl_scratch_pool_free(p);
	return 0;
}

static int l_pool_tostring(lua_State *L)
{
	struct jnl_scratch_pool *p = check_pool(L, 1);
	lua_pushfstring(L,
	                "scratch_pool(len=%d, n_buf=%d, in_use=%d, high_water=%d)",
	                p->len, p->n_buf, p->n_in_use, p->high_water);
	return 1;
}

static int l_pool_reset(lua_State *L)
{
	jnl_scratch_reset(check_pool(L, 1));
	return 0;
}

static int l_pool_len(lua_State *L)
{
	lua_pushinteger(L, check_pool(L, 1)->len);
	return 1;
}

static int l_pool_n_buf(lua_State *L)
{
	lua_pushinteger(L, check_pool(L, 1)->n_buf);
	return 1;
}

static int l_pool_in_use(lua_State *L)
{
	lua_pushinteger(L, check_pool(L, 1)->n_in_use);
	return 1;
}

static int l_pool_high_water(lua_State *L)
{
	lua_pushinteger(L, check_pool(L, 1)->high_water);
	return 1;
}

/*
 * Registration
 */

static const luaL_Reg pool_mt[] = {{"reset", l_pool_reset},
                                   {"len", l_pool_len},
                                   {"n_buf", l_pool_n_buf},
                                   {"in_use", l_pool_in_use},
                                   {"high_water", l_pool_high_water},
                                   {"__tostring", l_pool_tostring},
                                   {"__gc", l_pool_gc},
                                   {NULL, NULL}};

static const luaL_Reg pool_funcs[] = {
    {"new", l_pool_new},
    {NULL, NULL},
};

int luaopen_scratch_internal(lua_State *L)
{
	luaL_newmetatable(L, POOL_MT);
	luaL_setfuncs(L, pool_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, pool_funcs);
	return 1;
}
