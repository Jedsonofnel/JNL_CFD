#include <string.h>

#include "lua_bindings.h"
#include "vec.h"

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

static int l_vec_max(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_pushnumber(L, jnl_vec_max(v->data, v->len));
	return 1;
}

static int l_vec_min(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_pushnumber(L, jnl_vec_min(v->data, v->len));
	return 1;
}

static int l_vec_sum(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_pushnumber(L, jnl_vec_sum(v->data, v->len));
	return 1;
}

static int l_vec_mean(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_pushnumber(L, jnl_vec_mean(v->data, v->len));
	return 1;
}

static int l_vec_scale(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 alpha = luaL_checknumber(L, 2);
	jnl_vec_scale(v->data, alpha, v->len);
	return 0;
}

// v:axpy(alpha, w)  =>  v += alpha * w
static int l_vec_axpy(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 alpha = luaL_checknumber(L, 2);
	lua_vec *w = check_vec(L, 3);
	luaL_argcheck(L, v->len == w->len, 3, "vec size mismatch");
	jnl_vec_axpy(v->data, alpha, w->data, v->len);
	return 0;
}

static int l_vec_clamp(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 lo = luaL_checknumber(L, 2);
	f64 hi = luaL_checknumber(L, 3);
	luaL_argcheck(L, lo <= hi, 3, "clamp: lo must be <= hi");
	jnl_vec_clamp(v->data, lo, hi, v->len);
	return 0;
}

static int l_vec_dot(lua_State *L)
{
	lua_vec *a = check_vec(L, 1);
	lua_vec *b = check_vec(L, 2);
	luaL_argcheck(L, a->len == b->len, 2, "vec size mismatch");
	lua_pushnumber(L, jnl_vec_dot(a->data, b->data, a->len));
	return 1;
}

//
// Norms
//

static int l_vec_norm_l1(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 norm = jnl_vec_norm_l1(v->data, v->len);
	lua_pushnumber(L, norm);
	return 1;
}

static int l_vec_norm_l2(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 norm = jnl_vec_norm_l2(v->data, v->len);
	lua_pushnumber(L, norm);
	return 1;
}

static int l_vec_norm_linf(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	f64 norm = jnl_vec_norm_linf(v->data, v->len);
	lua_pushnumber(L, norm);
	return 1;
}

static int l_vec_norm_l2_rel(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_vec *ref = check_vec(L, 2);
	f64 norm = jnl_vec_norm_l2_rel(v->data, ref->data, v->len);
	lua_pushnumber(L, norm);
	return 1;
}

static int l_vec_norm_l2_rel_diff(lua_State *L)
{
	lua_vec *new = check_vec(L, 1);
	lua_vec *old = check_vec(L, 2);
	f64 norm = jnl_vec_norm_l2_rel_diff(new->data, old->data, new->len);
	lua_pushnumber(L, norm);
	return 1;
}

static int l_vec_norm_l2_weighted(lua_State *L)
{
	lua_vec *v = check_vec(L, 1);
	lua_vec *weights = check_vec(L, 2);
	f64 norm = jnl_vec_norm_l2_weighted(v->data, weights->data, v->len);
	lua_pushnumber(L, norm);
	return 1;
}

//
// Registration
//

static const luaL_Reg vec_mt[] = {{"fill", l_vec_fill},
                                  {"copy_from", l_vec_copy_from},
                                  {"norm_l1", l_vec_norm_l1},
                                  {"max", l_vec_max},
                                  {"norm_l2", l_vec_norm_l2},
                                  {"norm_linf", l_vec_norm_linf},
                                  {"norm_l2_rel", l_vec_norm_l2_rel},
                                  {"norm_l2_rel_diff", l_vec_norm_l2_rel_diff},
                                  {"norm_l2_weighted", l_vec_norm_l2_weighted},
                                  {"min", l_vec_min},
                                  {"sum", l_vec_sum},
                                  {"mean", l_vec_mean},
                                  {"scale", l_vec_scale},
                                  {"axpy", l_vec_axpy},
                                  {"clamp", l_vec_clamp},
                                  {"dot", l_vec_dot},
                                  {"__newindex", l_vec_newindex},
                                  {"__len", l_vec_len},
                                  {"__tostring", l_vec_tostring},
                                  {"__gc", l_vec_gc},
                                  {NULL, NULL}};

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
