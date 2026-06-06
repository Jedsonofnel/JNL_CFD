#ifndef JNL_LUA_BINDINGS_H
#define JNL_LUA_BINDINGS_H

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "jnl/common.h"

#define PSLG_MT "jnl.geo2d.pslg"
#define MESH_MT "jnl.mesh2d.mesh"
#define VEC_MT "jnl.vec"
#define POOL_MT "jnl.scratch_pool"

//
// Shared vec userdata - f64* slice
//

typedef struct {
	f64 *data;
	i32 len;
	int ctx_ref; // LUA_NOREF = unowned scratch, else luaL_ref anchor
} lua_vec;

static inline lua_vec *check_vec(lua_State *L, int idx)
{
	return (lua_vec *)luaL_checkudata(L, idx, VEC_MT);
}

// Push an unowned scratch vec (data borrowed, no GC cleanup)
static inline void push_scratch_vec(lua_State *L, f64 *data, i32 len)
{
	lua_vec *v = (lua_vec *)lua_newuserdata(L, sizeof(lua_vec));
	v->data = data;
	v->len = len;
	v->ctx_ref = LUA_NOREF;
	luaL_setmetatable(L, VEC_MT);
}

// Push an owned vec with a GC anchor keeping parent alive
static inline void push_owned_vec(lua_State *L, f64 *data, i32 len,
                                  int parent_idx)
{
	lua_vec *v = (lua_vec *)lua_newuserdata(L, sizeof(lua_vec));
	v->data = data;
	v->len = len;
	lua_pushvalue(L, parent_idx);
	v->ctx_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	luaL_setmetatable(L, VEC_MT);
}

//
// Shared scratch pool userdata
//

typedef struct jnl_scratch_pool lua_pool;

static inline struct jnl_scratch_pool *check_pool(lua_State *L, int idx)
{
	return *(struct jnl_scratch_pool **)luaL_checkudata(L, idx, POOL_MT);
}

static inline void
push_borrowed_pool(lua_State *L, struct jnl_scratch_pool *pool, int parent_idx)
{
	struct jnl_scratch_pool **pp = lua_newuserdata(L, sizeof(void *));
	*pp = pool;
	lua_pushvalue(L, parent_idx);
	lua_setuservalue(L, -2);
	luaL_setmetatable(L, POOL_MT);
}

//
// Module openers
//

int luaopen_vec_internal(lua_State *L);
int luaopen_expr_internal(lua_State *L);
int luaopen_scratch_internal(lua_State *L);
int luaopen_vtk_internal(lua_State *L);

int luaopen_pslg2d_internal(lua_State *L);
int luaopen_mesh2d_internal(lua_State *L);
int luaopen_ui_internal(lua_State *L);
int luaopen_fvm_internal(lua_State *L);

// bit of a smell but small enough that it's fine
static inline void register_preloaders(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");

	lua_pushcfunction(L, luaopen_vec_internal);
	lua_setfield(L, -2, "jnl.vec_internal");

	lua_pushcfunction(L, luaopen_scratch_internal);
	lua_setfield(L, -2, "jnl.scratch_internal");

	lua_pushcfunction(L, luaopen_expr_internal);
	lua_setfield(L, -2, "jnl.expr_internal");

	lua_pushcfunction(L, luaopen_vtk_internal);
	lua_setfield(L, -2, "jnl.vtk_internal");

	lua_pushcfunction(L, luaopen_pslg2d_internal);
	lua_setfield(L, -2, "jnl.geo2d_internal");

	lua_pushcfunction(L, luaopen_ui_internal);
	lua_setfield(L, -2, "jnl.ui_internal");

	lua_pushcfunction(L, luaopen_mesh2d_internal);
	lua_setfield(L, -2, "jnl.mesh2d_internal");

	lua_pushcfunction(L, luaopen_fvm_internal);
	lua_setfield(L, -2, "jnl.fvm_internal");

	lua_pop(L, 2);
}

#endif // JNL_LUA_BINDINGS_H
