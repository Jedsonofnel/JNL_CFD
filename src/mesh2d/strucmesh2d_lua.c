#include <lauxlib.h>
#include <lua.h>
#include <string.h>

#include "lua_bindings.h"
#include "jnl/common.h"
#include "mesh2d/polymesh2d.h"
#include "mesh2d/cartmesh2d.h"
#include "mesh2d/strucmesh2d.h"
#include "geo2d/curve2d.h"

#define BLOCK_MT "jnl.strucmesh2d.block"
#define GRID_MT "jnl.strucmesh2d.grid"

//
// Userdata checks
//

static struct jnl_struc2d_block *check_block(lua_State *L, int idx)
{
	return (struct jnl_struc2d_block *)luaL_checkudata(L, idx, BLOCK_MT);
}

static struct jnl_struc2d_grid *check_grid(lua_State *L, int idx)
{
	return (struct jnl_struc2d_grid *)luaL_checkudata(L, idx, GRID_MT);
}

// Shared helper: push a heap-allocated polymesh2d as a Lua userdata.
// MESH_MT must already be registered (guaranteed by luaopen dependency).
static void push_mesh(lua_State *L, pmsh2d *mesh)
{
	pmsh2d **mp = lua_newuserdata(L, sizeof(*mp));
	*mp = mesh;
	luaL_setmetatable(L, MESH_MT);
}

//
// Cartesian mesh
//
// cartmesh(width, height, nx, ny) -> mesh, nil
//                                 -> nil,  errmsg
//

static int l_cartmesh_gen(lua_State *L)
{
	struct jnl_cartmesh2d_opts opts = jnl_cartmesh2d_opts_default();
	opts.width = luaL_checknumber(L, 1);
	opts.height = luaL_checknumber(L, 2);
	opts.nx = (u32)luaL_checkinteger(L, 3);
	opts.ny = (u32)luaL_checkinteger(L, 4);

	pmsh2d *mesh = NULL;
	enum jnl_mesh_err err = jnl_cartmesh2d_build(&opts, &mesh);
	if (err != JNL_MESH_OK) {
		lua_pushnil(L);
		lua_pushstring(L, jnl_mesh_err_str(err));
		return 2;
	}
	push_mesh(L, mesh);
	lua_pushnil(L);
	return 2;
}

//
// Block lifecycle
//

// block_new(ni, nj) -> block
static int l_block_new(lua_State *L)
{
	i32 ni = (i32)luaL_checkinteger(L, 1);
	i32 nj = (i32)luaL_checkinteger(L, 2);

	// Allocate userdata and zero it before setting the metatable so that
	// if alloc fails and we luaL_error, the __gc sees zeroed x/y pointers.
	struct jnl_struc2d_block *b = lua_newuserdata(L, sizeof(*b));
	memset(b, 0, sizeof(*b));
	luaL_setmetatable(L, BLOCK_MT);

	enum jnl_struc2d_err e = jnl_struc2d_block_alloc(b, ni, nj);
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "block_new: %s", jnl_struc2d_err_str(e));

	return 1;
}

static int l_block_gc(lua_State *L)
{
	jnl_struc2d_block_free(check_block(L, 1));
	return 0;
}

static int l_block_tostring(lua_State *L)
{
	struct jnl_struc2d_block *b = check_block(L, 1);
	lua_pushfstring(L, "jnl.struc2d.block(%d x %d)", b->ni, b->nj);
	return 1;
}

//
// Block methods
//

static int l_block_set_edge_marker(lua_State *L)
{
	struct jnl_struc2d_block *b = check_block(L, 1);
	enum jnl_struc2d_edge edge = (enum jnl_struc2d_edge)luaL_checkinteger(L, 2);
	i32 marker = (i32)luaL_checkinteger(L, 3);
	jnl_struc2d_block_set_edge_marker(b, edge, marker);
	return 0;
}

static int l_block_set_region_marker(lua_State *L)
{
	jnl_struc2d_block_set_region_marker(check_block(L, 1),
	                                    (i32)luaL_checkinteger(L, 2));
	return 0;
}

// block:sample_edge(edge, curve, dist)
static int l_block_sample_edge(lua_State *L)
{
	struct jnl_struc2d_block *b = check_block(L, 1);
	enum jnl_struc2d_edge edge = (enum jnl_struc2d_edge)luaL_checkinteger(L, 2);
	struct jnl_curve2d *c =
	    (struct jnl_curve2d *)luaL_checkudata(L, 3, CURVE2D_MT);
	struct jnl_dist1d *d =
	    (struct jnl_dist1d *)luaL_checkudata(L, 4, DIST1D_MT);

	enum jnl_struc2d_err e = jnl_struc2d_block_sample_edge(b, edge, c, d);
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "sample_edge: %s", jnl_struc2d_err_str(e));
	return 0;
}

// block:copy_edge(dst_edge, src_block, src_edge [, reversed=false])
static int l_block_copy_edge(lua_State *L)
{
	struct jnl_struc2d_block *dst = check_block(L, 1);
	enum jnl_struc2d_edge dst_edge =
	    (enum jnl_struc2d_edge)luaL_checkinteger(L, 2);
	struct jnl_struc2d_block *src = check_block(L, 3);
	enum jnl_struc2d_edge src_edge =
	    (enum jnl_struc2d_edge)luaL_checkinteger(L, 4);
	bool reversed = lua_toboolean(L, 5);

	enum jnl_struc2d_err e =
	    jnl_struc2d_block_copy_edge(dst, dst_edge, src, src_edge, reversed);
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "copy_edge: %s", jnl_struc2d_err_str(e));
	return 0;
}

static int l_block_tfi(lua_State *L)
{
	enum jnl_struc2d_err e = jnl_struc2d_block_tfi(check_block(L, 1));
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "tfi: %s", jnl_struc2d_err_str(e));
	return 0;
}

// block:smooth([{ max_iter=, omega=, tol= }])
static int l_block_smooth(lua_State *L)
{
	struct jnl_struc2d_block *b = check_block(L, 1);
	struct jnl_struc2d_smooth_opts opts = jnl_struc2d_smooth_opts_default();

	if (lua_istable(L, 2)) {
		lua_getfield(L, 2, "max_iter");
		if (!lua_isnil(L, -1))
			opts.max_iter = (i32)lua_tointeger(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 2, "omega");
		if (!lua_isnil(L, -1))
			opts.omega = lua_tonumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, 2, "tol");
		if (!lua_isnil(L, -1))
			opts.tol = lua_tonumber(L, -1);
		lua_pop(L, 1);
	}

	enum jnl_struc2d_err e = jnl_struc2d_block_smooth_laplace(b, &opts);
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "smooth: %s", jnl_struc2d_err_str(e));
	return 0;
}

// block:build() -> mesh, nil | nil, errmsg
static int l_block_build(lua_State *L)
{
	struct jnl_struc2d_block *b = check_block(L, 1);
	pmsh2d *mesh = NULL;
	enum jnl_struc2d_err e = jnl_struc2d_block_build(b, &mesh);
	if (e != JNL_STRUC2D_OK) {
		lua_pushnil(L);
		lua_pushstring(L, jnl_struc2d_err_str(e));
		return 2;
	}
	push_mesh(L, mesh);
	lua_pushnil(L);
	return 2;
}

static const luaL_Reg block_methods[] = {
    {"set_edge_marker", l_block_set_edge_marker},
    {"set_region_marker", l_block_set_region_marker},
    {"sample_edge", l_block_sample_edge},
    {"copy_edge", l_block_copy_edge},
    {"tfi", l_block_tfi},
    {"smooth", l_block_smooth},
    {"build", l_block_build},
    {"__tostring", l_block_tostring},
    {"__gc", l_block_gc},
    {NULL, NULL},
};

//
// Grid lifecycle
//

static int l_grid_new(lua_State *L)
{
	struct jnl_struc2d_grid *g = lua_newuserdata(L, sizeof(*g));
	jnl_struc2d_grid_init(g);
	luaL_setmetatable(L, GRID_MT);
	return 1;
}

static int l_grid_gc(lua_State *L)
{
	jnl_struc2d_grid_free(check_grid(L, 1));
	return 0;
}

static int l_grid_tostring(lua_State *L)
{
	struct jnl_struc2d_grid *g = check_grid(L, 1);
	lua_pushfstring(L, "jnl.struc2d.grid(%d blocks, %d joins)", g->n_blocks,
	                g->n_joins);
	return 1;
}

//
// Grid methods
//

// grid:add_block(block) -> id
static int l_grid_add_block(lua_State *L)
{
	struct jnl_struc2d_grid *g = check_grid(L, 1);
	struct jnl_struc2d_block *b = check_block(L, 2);
	i32 id = -1;
	enum jnl_struc2d_err e = jnl_struc2d_grid_add_block(g, b, &id);
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "add_block: %s", jnl_struc2d_err_str(e));
	lua_pushinteger(L, id);
	return 1;
}

// grid:add_join(id0, edge0, id1, edge1 [, reversed=false])
static int l_grid_add_join(lua_State *L)
{
	struct jnl_struc2d_grid *g = check_grid(L, 1);
	i32 block0 = (i32)luaL_checkinteger(L, 2);
	enum jnl_struc2d_edge edge0 =
	    (enum jnl_struc2d_edge)luaL_checkinteger(L, 3);
	i32 block1 = (i32)luaL_checkinteger(L, 4);
	enum jnl_struc2d_edge edge1 =
	    (enum jnl_struc2d_edge)luaL_checkinteger(L, 5);
	bool reversed = lua_toboolean(L, 6);

	enum jnl_struc2d_err e =
	    jnl_struc2d_grid_add_join(g, block0, edge0, block1, edge1, reversed);
	if (e != JNL_STRUC2D_OK)
		return luaL_error(L, "add_join: %s", jnl_struc2d_err_str(e));
	return 0;
}

// grid:check() -> ok (bool), errmsg
static int l_grid_check(lua_State *L)
{
	enum jnl_struc2d_err e = jnl_struc2d_grid_check(check_grid(L, 1));
	lua_pushboolean(L, e == JNL_STRUC2D_OK);
	lua_pushstring(L, jnl_struc2d_err_str(e));
	return 2;
}

// grid:build() -> mesh, nil | nil, errmsg
static int l_grid_build(lua_State *L)
{
	struct jnl_struc2d_grid *g = check_grid(L, 1);
	pmsh2d *mesh = NULL;
	enum jnl_struc2d_err e = jnl_struc2d_grid_build(g, &mesh);
	if (e != JNL_STRUC2D_OK) {
		lua_pushnil(L);
		lua_pushstring(L, jnl_struc2d_err_str(e));
		return 2;
	}
	push_mesh(L, mesh);
	lua_pushnil(L);
	return 2;
}

static const luaL_Reg grid_methods[] = {
    {"add_block", l_grid_add_block},
    {"add_join", l_grid_add_join},
    {"check", l_grid_check},
    {"build", l_grid_build},
    {"__tostring", l_grid_tostring},
    {"__gc", l_grid_gc},
    {NULL, NULL},
};

//
// Module functions
//

static const luaL_Reg strucmesh2d_funcs[] = {
    {"cartmesh", l_cartmesh_gen},
    {"block_new", l_block_new},
    {"grid_new", l_grid_new},
    {NULL, NULL},
};

static void register_mt(lua_State *L, const char *name, const luaL_Reg *methods)
{
	luaL_newmetatable(L, name);
	luaL_setfuncs(L, methods, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

int luaopen_strucmesh2d_internal(lua_State *L)
{
	// Ensure MESH_MT is registered before we start producing meshes.
	luaL_requiref(L, "jnl.mesh2d_internal", luaopen_mesh2d_internal, 0);
	lua_pop(L, 1);

	register_mt(L, BLOCK_MT, block_methods);
	register_mt(L, GRID_MT, grid_methods);

	luaL_newlib(L, strucmesh2d_funcs);

	// Edge constants
	lua_pushinteger(L, JNL_STRUC2D_SOUTH);
	lua_setfield(L, -2, "SOUTH");
	lua_pushinteger(L, JNL_STRUC2D_EAST);
	lua_setfield(L, -2, "EAST");
	lua_pushinteger(L, JNL_STRUC2D_NORTH);
	lua_setfield(L, -2, "NORTH");
	lua_pushinteger(L, JNL_STRUC2D_WEST);
	lua_setfield(L, -2, "WEST");

	return 1;
}
