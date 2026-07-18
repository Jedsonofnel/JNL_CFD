#ifndef JNL_LUA_BINDINGS_H
#define JNL_LUA_BINDINGS_H

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "jnl/common.h"
#include "mesh2d.h"

#define VEC_MT "jnl.vec"

#define PSLG_MT "jnl.geo2d.pslg"
#define CURVE2D_MT "jnl.geo2d.curve"
#define DIST1D_MT "jnl.geo2d.dist"
#define DOMAIN2D_MT "jnl.geo2d.domain"

#define MESH_MT "jnl.mesh2d.mesh"
#define POOL_MT "jnl.scratch_pool"

#define FVSYS_MT "jnl.fvm.fvsys"

#define CG_JAC_SOLVE_MT "jnl.fvm.cg_jac_solve"
#define CG_DIC_SOLVE_MT "jnl.fvm.cg_dic_solve"
#define BICGSTAB_JAC_SOLVE_MT "jnl.fvm.bicgstab_jac_solve"
#define BICGSTAB_DILU_SOLVE_MT "jnl.fvm.bicgstab_dilu_solve"
#define GMRES_DILU_SOLVE_MT "jnl.fvm.gmres_dilu_solve"
#define JACOBI_SMOOTHER_MT "jnl.fvm.jacobi_smoother"

//
// Shared vec userdata - f64* slice
//

typedef struct {
	f64 *data;
	i32 len;
	bool owned;     // true -> free(data) on __gc
	int anchor_ref; // LUA_NOREF, or ref keeping source alive for views
} lua_vec;

static inline lua_vec *check_vec(lua_State *L, int idx)
{
	return (lua_vec *)luaL_checkudata(L, idx, VEC_MT);
}

// owned: vec malloc'd this data, frees it on GC
static inline void push_owned_vec(lua_State *L, f64 *data, i32 len)
{
	lua_vec *v = (lua_vec *)lua_newuserdata(L, sizeof(lua_vec));
	v->data = data;
	v->len = len;
	v->owned = true;
	v->anchor_ref = LUA_NOREF;
	luaL_setmetatable(L, VEC_MT);
}

// view: borrows data from another object, anchors it to prevent GC
static inline void push_view_vec(lua_State *L, f64 *data, i32 len, int src_idx)
{
	lua_vec *v = (lua_vec *)lua_newuserdata(L, sizeof(lua_vec));
	v->data = data;
	v->len = len;
	v->owned = false;
	lua_pushvalue(L, src_idx);
	v->anchor_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	luaL_setmetatable(L, VEC_MT);
}

// scratch: borrowed from pool, pool owns it, no GC action needed
static inline void push_scratch_vec(lua_State *L, f64 *data, i32 len)
{
	lua_vec *v = (lua_vec *)lua_newuserdata(L, sizeof(lua_vec));
	v->data = data;
	v->len = len;
	v->owned = false;
	v->anchor_ref = LUA_NOREF;
	luaL_setmetatable(L, VEC_MT);
}

//
// Shared mesh userdata
//

static inline pmsh2d *check_pmsh2d(lua_State *L, int idx)
{
	return *(pmsh2d **)luaL_checkudata(L, idx, MESH_MT);
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
// FVM userdata shared across split files
//

static inline struct jnl_fvsys *check_fvsys(lua_State *L, int idx)
{
	return *(struct jnl_fvsys **)luaL_checkudata(L, idx, FVSYS_MT);
}

//
// FVM submodule registration helpers
//

void jnl_lua_register_fvm_operators(lua_State *L);
void jnl_lua_register_fvm_bc(lua_State *L);
void jnl_lua_register_fvm_field(lua_State *L);
void jnl_lua_register_fvm_solver(lua_State *L);

//
// Module openers
//

int luaopen_vec_internal(lua_State *L);
int luaopen_expr_internal(lua_State *L);
int luaopen_scratch_internal(lua_State *L);
int luaopen_vtk_internal(lua_State *L);

int luaopen_domain2d_internal(lua_State *L);
int luaopen_pslg2d_internal(lua_State *L);
int luaopen_curve2d_internal(lua_State *L);

int luaopen_mesh2d_internal(lua_State *L);
int luaopen_strucmesh2d_internal(lua_State *L);
int luaopen_trimesh2d_internal(lua_State *L);

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

	lua_pushcfunction(L, luaopen_domain2d_internal);
	lua_setfield(L, -2, "jnl.domain2d_internal");

	lua_pushcfunction(L, luaopen_pslg2d_internal);
	lua_setfield(L, -2, "jnl.pslg2d_internal");

	lua_pushcfunction(L, luaopen_curve2d_internal);
	lua_setfield(L, -2, "jnl.curve2d_internal");

	lua_pushcfunction(L, luaopen_ui_internal);
	lua_setfield(L, -2, "jnl.ui_internal");

	lua_pushcfunction(L, luaopen_mesh2d_internal);
	lua_setfield(L, -2, "jnl.mesh2d_internal");

	lua_pushcfunction(L, luaopen_strucmesh2d_internal);
	lua_setfield(L, -2, "jnl.strucmesh2d_internal");

	lua_pushcfunction(L, luaopen_trimesh2d_internal);
	lua_setfield(L, -2, "jnl.trimesh2d_internal");

	lua_pushcfunction(L, luaopen_fvm_internal);
	lua_setfield(L, -2, "jnl.fvm_internal");

	lua_pop(L, 2);
}

#endif // JNL_LUA_BINDINGS_H
