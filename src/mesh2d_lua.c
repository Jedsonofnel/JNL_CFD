#include <lauxlib.h>
#include <lua.h>
#include <string.h>

#include "lua_bindings.h"
#include "jnl/common.h"
#include "mesh2d.h"

//
// Mesh API
//

static struct jnl_mesh *check_mesh(lua_State *L, int idx)
{
	return *(struct jnl_mesh **)luaL_checkudata(L, idx, MESH_MT);
}

static int l_smesh_gen(lua_State *L)
{
	f64 width = luaL_checknumber(L, 1);
	f64 height = luaL_checknumber(L, 2);
	i32 nx = (i32)luaL_checkinteger(L, 3);
	i32 ny = (i32)luaL_checkinteger(L, 4);

	struct jnl_mesh **mesh = lua_newuserdata(L, sizeof(struct jnl_mesh *));
	*mesh = jnl_smesh_gen(width, height, nx, ny);
	luaL_setmetatable(L, MESH_MT);
	return 1;
}

static int l_mesh_gc(lua_State *L)
{
	struct jnl_mesh **mp = luaL_checkudata(L, 1, MESH_MT);
	if (*mp) {
		jnl_mesh_free(*mp);
		*mp = NULL;
	}
	return 0;
}

static int l_mesh_tostring(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_pushfstring(L, "jnl.mesh(%d cells, %d faces, %d patches)",
	                m->topo.n_cells, m->topo.n_faces, m->patches.n_patches);
	return 1;
}

static int l_mesh_n_cells(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_pushinteger(L, m->topo.n_cells);
	return 1;
}

static int l_mesh_n_faces(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_pushinteger(L, m->topo.n_faces);
	return 1;
}

static int l_mesh_n_internal_faces(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_pushinteger(L, m->topo.n_internal_faces);
	return 1;
}

static int l_mesh_n_patches(lua_State *L)
{
	lua_pushinteger(L, check_mesh(L, 1)->patches.n_patches);
	return 1;
}

// Returns patch table: { name, start_face, n_faces }
static int l_mesh_patches(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	struct jnl_patches *p = &m->patches;

	lua_createtable(L, p->n_patches, 0);
	for (int i = 0; i < p->n_patches; i++) {
		lua_createtable(L, 0, 3);
		lua_pushstring(L, p->data[i].name);
		lua_setfield(L, -2, "name");
		lua_pushinteger(L, p->data[i].start_face);
		lua_setfield(L, -2, "start_face");
		lua_pushinteger(L, p->data[i].n_faces);
		lua_setfield(L, -2, "n_faces");
		lua_rawseti(L, -2, i + 1);
	}
	return 1;
}

static int l_mesh_patch_by_name(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	const char *name = luaL_checkstring(L, 2);
	for (int i = 0; i < m->patches.n_patches; i++) {
		if (strcmp(m->patches.data[i].name, name) == 0) {
			lua_createtable(L, 0, 4);
			lua_pushstring(L, m->patches.data[i].name);
			lua_setfield(L, -2, "name");
			lua_pushinteger(L, m->patches.data[i].start_face);
			lua_setfield(L, -2, "start_face");
			lua_pushinteger(L, m->patches.data[i].n_faces);
			lua_setfield(L, -2, "n_faces");
			lua_pushinteger(L, m->patches.data[i].marker);
			lua_setfield(L, -2, "marker");
			return 1;
		}
	}
	lua_pushnil(L);
	return 1;
}

//
// Cell geometry accessors
//

static int l_mesh_cell_centre(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_cells, 2,
	              "cell index out of range");
	lua_pushnumber(L, m->geom.cell_cx[i]);
	lua_pushnumber(L, m->geom.cell_cy[i]);
	return 2;
}

static int l_mesh_face_centre(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_cx[i]);
	lua_pushnumber(L, m->geom.face_cy[i]);
	return 2;
}

static int l_mesh_cell_vol(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_cells, 2,
	              "cell index out of range");
	lua_pushnumber(L, m->geom.cell_vol[i]);
	return 1;
}

static const luaL_Reg mesh2d_methods[] = {
    {"n_cells", l_mesh_n_cells},
    {"n_faces", l_mesh_n_faces},
    {"n_internal_faces", l_mesh_n_internal_faces},
    {"patches", l_mesh_patches},
    {"n_patches", l_mesh_n_patches},
    {"patch_by_name", l_mesh_patch_by_name},
    {"cell_centre", l_mesh_cell_centre},
    {"face_centre", l_mesh_face_centre},
    {"cell_vol", l_mesh_cell_vol},
    {"__tostring", l_mesh_tostring},
    {"__gc", l_mesh_gc},
    {NULL, NULL},
};

static const luaL_Reg mesh2d_funcs[] = {{"smesh_gen", l_smesh_gen},
                                        {NULL, NULL}};

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
