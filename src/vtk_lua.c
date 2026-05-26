#include <stdlib.h>

#include "lua_bindings.h"
#include "mesh2d.h"
#include "vtk.h"

#define VTK_WRITER_MT "jnl.vtk.writer"

typedef struct {
	const struct jnl_mesh *mesh;
	const char *path;
	struct jnl_vtk_scalar *scalars;
	struct jnl_vtk_vector *vectors;
	int n_scalars;
	int n_vectors;
} lua_vtk_writer;

static lua_vtk_writer *check_writer(lua_State *L, int idx)
{
	return (lua_vtk_writer *)luaL_checkudata(L, idx, VTK_WRITER_MT);
}

static struct jnl_mesh *check_mesh(lua_State *L, int idx)
{
	return *(struct jnl_mesh **)luaL_checkudata(L, idx, MESH_MT);
}

// vtk.new(path, mesh) -> writer
static int l_vtk_new(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	struct jnl_mesh *mesh = check_mesh(L, 2);

	lua_vtk_writer *w = lua_newuserdata(L, sizeof(*w));
	w->mesh = mesh;
	w->path = path;
	w->scalars = NULL;
	w->vectors = NULL;
	w->n_scalars = 0;
	w->n_vectors = 0;
	luaL_setmetatable(L, VTK_WRITER_MT);
	return 1;
}

// writer:add_scalar(name, vec)
static int l_writer_add_scalar(lua_State *L)
{
	lua_vtk_writer *w = check_writer(L, 1);
	const char *name = luaL_checkstring(L, 2);
	lua_vec *v = (lua_vec *)luaL_checkudata(L, 3, VEC_MT);

	w->scalars =
	    realloc(w->scalars, (size_t)(w->n_scalars + 1) * sizeof(*w->scalars));
	w->scalars[w->n_scalars].name = name;
	w->scalars[w->n_scalars].data = v->data;
	w->n_scalars++;
	return 0;
}

// writer:add_vector(name, x_vec, y_vec)
static int l_writer_add_vector(lua_State *L)
{
	lua_vtk_writer *w = check_writer(L, 1);
	const char *name = luaL_checkstring(L, 2);
	lua_vec *x = (lua_vec *)luaL_checkudata(L, 3, VEC_MT);
	lua_vec *y = (lua_vec *)luaL_checkudata(L, 4, VEC_MT);

	w->vectors =
	    realloc(w->vectors, (size_t)(w->n_vectors + 1) * sizeof(*w->vectors));
	w->vectors[w->n_vectors].name = name;
	w->vectors[w->n_vectors].x = x->data;
	w->vectors[w->n_vectors].y = y->data;
	w->n_vectors++;
	return 0;
}

// writer:write()
static int l_writer_write(lua_State *L)
{
	lua_vtk_writer *w = check_writer(L, 1);

	/* Append NULL sentinels without storing them in the count */
	w->scalars =
	    realloc(w->scalars, (size_t)(w->n_scalars + 1) * sizeof(*w->scalars));
	w->scalars[w->n_scalars].name = NULL;

	w->vectors =
	    realloc(w->vectors, (size_t)(w->n_vectors + 1) * sizeof(*w->vectors));
	w->vectors[w->n_vectors].name = NULL;

	jnl_vtk_write(w->path, w->mesh, w->n_scalars ? w->scalars : NULL,
	              w->n_vectors ? w->vectors : NULL);
	return 0;
}

static int l_writer_gc(lua_State *L)
{
	lua_vtk_writer *w = check_writer(L, 1);
	free(w->scalars);
	free(w->vectors);
	return 0;
}

//
// Module registration
//

static const luaL_Reg writer_methods[] = {
    {"add_scalar", l_writer_add_scalar},
    {"add_vector", l_writer_add_vector},
    {"write", l_writer_write},
    {"__gc", l_writer_gc},
    {NULL, NULL},
};

static const luaL_Reg vtk_funcs[] = {
    {"new", l_vtk_new},
    {NULL, NULL},
};

int luaopen_vtk_internal(lua_State *L)
{
	luaL_newmetatable(L, VTK_WRITER_MT);
	luaL_setfuncs(L, writer_methods, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, vtk_funcs);
	return 1;
}
