#include <math.h>
#include <string.h>

#include "lua_bindings.h"

//
// Metamethods
//

static int l_vec_index(lua_State *L)
{
	if (lua_type(L, 2) == LUA_TNUMBER) {
		lua_vec *v = check_vec(L, 1);
		i32 i = (i32)lua_tointeger(L, 2) - 1;
		luaL_argcheck(L, i >= 0 && i < v->len, 2, "vec index out of range");
		lua_pushnumber(L, v->data[i]);
		return 1;
	}
	// fall through to method table
	luaL_getmetatable(L, VEC_MT);
	lua_pushvalue(L, 2);
	lua_rawget(L, -2);
	return 1;
}

static int l_vec_newindex(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < v->len, 2, "vec index out of range");
	v->data[i] = luaL_checknumber(L, 3);
	return 0;
}

static int l_vec_len(lua_State *L)
{
	lua_pushinteger(L, check_vec(L, 1)->len);
	return 1;
}

static int l_vec_tostring(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_pushfstring(L, "vec(len=%d, data=%p, %s)", v->len, v->data,
	                v->ctx_ref == LUA_NOREF ? "scratch" : "owned");
	return 1;
}

static int l_vec_gc(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	if (v->ctx_ref != LUA_NOREF)
		luaL_unref(L, LUA_REGISTRYINDEX, v->ctx_ref);
	return 0;
}

//
// Methods
//

static int l_vec_fill(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 val = luaL_checknumber(L, 2);
	for (i32 i = 0; i < v->len; i++)
		v->data[i] = val;
	return 0;
}

static int l_vec_copy_from(lua_State *L)
{
	lua_vec *dst = check_vec(L, 1);
	lua_vec *src = check_vec(L, 2);
	luaL_argcheck(L, dst->len == src->len, 2, "vec size mismatch");
	memcpy(dst->data, src->data, (u64)dst->len * sizeof(f64));
	return 0;
}

static int l_vec_norm(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 s = 0.0;
	for (i32 i = 0; i < v->len; i++)
		s += v->data[i] * v->data[i];
	lua_pushnumber(L, sqrt(s));
	return 1;
}

//
// Registration
//

static const luaL_Reg vec_mt[] = {
    {"fill", l_vec_fill}, {"copy_from", l_vec_copy_from},
    {"norm", l_vec_norm}, {"__newindex", l_vec_newindex},
    {"__len", l_vec_len}, {"__tostring", l_vec_tostring},
    {"__gc", l_vec_gc},   {NULL, NULL}};

int luaopen_vec_internal(lua_State *L)
{
	luaL_newmetatable(L, VEC_MT);
	luaL_setfuncs(L, vec_mt, 0);
	lua_pushcfunction(L, l_vec_index);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	lua_newtable(L);
	return 1;
}


