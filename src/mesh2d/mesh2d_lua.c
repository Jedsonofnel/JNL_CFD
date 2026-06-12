#include <lauxlib.h>
#include <lua.h>
#include <math.h>
#include <string.h>

#include "lua_bindings.h"
#include "jnl/common.h"
#include "mesh2d/polymesh2d.h"

//
// Mesh GC / tostring
//

static int l_mesh_gc(lua_State *L)
{
	pmsh2d **mp = luaL_checkudata(L, 1, MESH_MT);
	if (*mp) {
		jnl_polymesh2d_free(*mp);
		*mp = NULL;
	}
	return 0;
}

static int l_mesh_tostring(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	lua_pushfstring(L, "jnl.pmsh2d(%d real, %d ghost, %d faces, %d patches)",
	                m->topo.n_real_cells, m->topo.n_ghost_cells,
	                m->topo.n_faces, m->patches.n_patches);
	return 1;
}

//
// Topology counts
//

static int l_mesh_n_cells(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_real_cells);
	return 1;
}
static int l_mesh_n_total_cells(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_cells);
	return 1;
}
static int l_mesh_n_real_cells(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_real_cells);
	return 1;
}
static int l_mesh_n_ghost_cells(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_ghost_cells);
	return 1;
}
static int l_mesh_n_faces(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_faces);
	return 1;
}
static int l_mesh_n_internal_faces(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_internal_faces);
	return 1;
}
static int l_mesh_n_boundary_faces(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_boundary_faces);
	return 1;
}
static int l_mesh_n_baffle_faces(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->topo.n_baffle_faces);
	return 1;
}
static int l_mesh_n_patches(lua_State *L)
{
	lua_pushinteger(L, check_pmsh2d(L, 1)->patches.n_patches);
	return 1;
}

//
// Patches
//

static void push_patch_table(lua_State *L, const struct jnl_pmsh2d_patch *p)
{
	lua_createtable(L, 0, 4);
	lua_pushstring(L, p->name);
	lua_setfield(L, -2, "name");
	lua_pushinteger(L, p->start_face);
	lua_setfield(L, -2, "start_face");
	lua_pushinteger(L, p->n_faces);
	lua_setfield(L, -2, "n_faces");
	lua_pushinteger(L, p->marker);
	lua_setfield(L, -2, "marker");
}

static int l_mesh_patches(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	lua_createtable(L, m->patches.n_patches, 0);
	for (int i = 0; i < m->patches.n_patches; i++) {
		push_patch_table(L, &m->patches.data[i]);
		lua_rawseti(L, -2, i + 1);
	}
	return 1;
}

static int l_mesh_patch_by_name(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	const char *name = luaL_checkstring(L, 2);
	for (int i = 0; i < m->patches.n_patches; i++) {
		if (strcmp(m->patches.data[i].name, name) == 0) {
			push_patch_table(L, &m->patches.data[i]);
			return 1;
		}
	}
	lua_pushnil(L);
	return 1;
}

//
// Cell geometry — 1-indexed
//

static int l_mesh_cell_centre(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_real_cells, 2,
	              "real cell index out of range");
	lua_pushnumber(L, m->geom.cell_cx[i]);
	lua_pushnumber(L, m->geom.cell_cy[i]);
	return 2;
}

static int l_mesh_cell_vol(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_real_cells, 2,
	              "cell index out of range");
	lua_pushnumber(L, m->geom.cell_vol[i]);
	return 1;
}

static int l_mesh_mean_cell_size(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	f64 total = 0.0;
	for (i32 i = 0; i < m->topo.n_real_cells; i++)
		total += m->geom.cell_vol[i];
	lua_pushnumber(L, sqrt(total / m->topo.n_real_cells));
	return 1;
}

//
// Face geometry — 1-indexed
//

static int l_mesh_face_centre(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_cx[i]);
	lua_pushnumber(L, m->geom.face_cy[i]);
	return 2;
}

static int l_mesh_face_normal(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_nx[i]);
	lua_pushnumber(L, m->geom.face_ny[i]);
	return 2;
}

//
// Face queries — 0-indexed (solver-internal use)
//

static int l_mesh_face_owner0(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);
	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushinteger(L, m->topo.owner[f]);
	return 1;
}

static int l_mesh_face_neighbour0(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);
	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushinteger(L, m->topo.neighbour[f]);
	return 1;
}

static int l_mesh_face_centre0(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);
	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_cx[f]);
	lua_pushnumber(L, m->geom.face_cy[f]);
	return 2;
}

static int l_mesh_face_normal0(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);
	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_nx[f]);
	lua_pushnumber(L, m->geom.face_ny[f]);
	return 2;
}

static int l_mesh_face_area0(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);
	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_area[f]);
	return 1;
}

//
// Bulk vec accessors — owned slices, keep parent alive via ctx_ref
//

static int l_mesh_cell_cx_vec(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	push_owned_vec(L, m->geom.cell_cx, m->topo.n_real_cells, 1);
	return 1;
}

static int l_mesh_cell_cy_vec(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	push_owned_vec(L, m->geom.cell_cy, m->topo.n_real_cells,
	               1); /* was cell_cx — bug fixed */
	return 1;
}

static int l_mesh_cell_vol_vec(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	push_owned_vec(L, m->geom.cell_vol, m->topo.n_real_cells,
	               1); /* was cell_cx — bug fixed */
	return 1;
}

//
// Type predicate — useful from Lua for dispatch/guards
//

static int l_is_mesh(lua_State *L)
{
	lua_pushboolean(L, luaL_testudata(L, 1, MESH_MT) != NULL);
	return 1;
}

//
// Method table
//

static const luaL_Reg mesh2d_methods[] = {
    /* topology counts */
    {"n_cells", l_mesh_n_cells},
    {"n_total_cells", l_mesh_n_total_cells},
    {"n_real_cells", l_mesh_n_real_cells},
    {"n_ghost_cells", l_mesh_n_ghost_cells},
    {"n_faces", l_mesh_n_faces},
    {"n_internal_faces", l_mesh_n_internal_faces},
    {"n_boundary_faces", l_mesh_n_boundary_faces},
    {"n_baffle_faces", l_mesh_n_baffle_faces},
    /* patches */
    {"patches", l_mesh_patches},
    {"n_patches", l_mesh_n_patches},
    {"patch_by_name", l_mesh_patch_by_name},
    /* 1-indexed cell */
    {"cell_centre", l_mesh_cell_centre},
    {"cell_vol", l_mesh_cell_vol},
    {"mean_cell_size", l_mesh_mean_cell_size},
    /* 1-indexed face */
    {"face_centre", l_mesh_face_centre},
    {"face_normal", l_mesh_face_normal},
    /* 0-indexed face */
    {"face_owner0", l_mesh_face_owner0},
    {"face_neighbour0", l_mesh_face_neighbour0},
    {"face_centre0", l_mesh_face_centre0},
    {"face_normal0", l_mesh_face_normal0},
    {"face_area0", l_mesh_face_area0},
    /* bulk vecs */
    {"cell_cx_vec", l_mesh_cell_cx_vec},
    {"cell_cy_vec", l_mesh_cell_cy_vec},
    {"cell_vol_vec", l_mesh_cell_vol_vec},
    /* metamethods */
    {"__tostring", l_mesh_tostring},
    {"__gc", l_mesh_gc},
    {NULL, NULL},
};

static const luaL_Reg mesh2d_funcs[] = {
    {"is_mesh", l_is_mesh},
    {NULL, NULL},
};

int luaopen_mesh2d_internal(lua_State *L)
{
	luaL_newmetatable(L, MESH_MT);
	luaL_setfuncs(L, mesh2d_methods, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, mesh2d_funcs);
	return 1;
}
