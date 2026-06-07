#include <stdlib.h>

#include "lua_bindings.h"
#include "mesh2d.h"
#include "vtk.h"

#define VTK_WRITER_MT "jnl.vtk.writer"

typedef struct {
	const pmsh2d *mesh;
	const char *path;

	struct jnl_vtk_scalar *scalars;
	struct jnl_vtk_vector *vectors;

	int n_scalars;
	int n_vectors;

	int mesh_ref;
} lua_vtk_writer;

static lua_vtk_writer *check_writer(lua_State *L, int idx)
{
	return (lua_vtk_writer *)luaL_checkudata(L, idx, VTK_WRITER_MT);
}

// vtk.new(path, mesh) -> writer
static int l_vtk_new(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	pmsh2d *mesh = check_pmsh2d(L, 2);

	lua_vtk_writer *w = lua_newuserdata(L, sizeof(*w));

	w->mesh = mesh;
	w->path = path;
	w->scalars = NULL;
	w->vectors = NULL;
	w->n_scalars = 0;
	w->n_vectors = 0;

	/*
	 * Keep the mesh userdata alive while this writer exists.
	 */
	lua_pushvalue(L, 2);
	w->mesh_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, VTK_WRITER_MT);
	return 1;
}

// writer:add_scalar(name, vec)
static int l_writer_add_scalar(lua_State *L)
{
	lua_vtk_writer *w = check_writer(L, 1);
	const char *name = luaL_checkstring(L, 2);
	lua_vec *v = check_vec(L, 3);

	struct jnl_vtk_scalar *new_scalars =
	    realloc(w->scalars, (size_t)(w->n_scalars + 1) * sizeof(*w->scalars));

	if (!new_scalars)
		return luaL_error(L, "vtk writer: scalar realloc failed");

	w->scalars = new_scalars;

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
	lua_vec *x = check_vec(L, 3);
	lua_vec *y = check_vec(L, 4);

	struct jnl_vtk_vector *new_vectors =
	    realloc(w->vectors, (size_t)(w->n_vectors + 1) * sizeof(*w->vectors));

	if (!new_vectors)
		return luaL_error(L, "vtk writer: vector realloc failed");

	w->vectors = new_vectors;

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

	struct jnl_vtk_scalar *scalars = NULL;
	struct jnl_vtk_vector *vectors = NULL;

	if (w->n_scalars > 0) {
		scalars = realloc(w->scalars,
		                  (size_t)(w->n_scalars + 1) * sizeof(*w->scalars));

		if (!scalars)
			return luaL_error(L, "vtk writer: scalar sentinel realloc failed");

		w->scalars = scalars;
		w->scalars[w->n_scalars].name = NULL;
		w->scalars[w->n_scalars].data = NULL;
		scalars = w->scalars;
	}

	if (w->n_vectors > 0) {
		vectors = realloc(w->vectors,
		                  (size_t)(w->n_vectors + 1) * sizeof(*w->vectors));

		if (!vectors)
			return luaL_error(L, "vtk writer: vector sentinel realloc failed");

		w->vectors = vectors;
		w->vectors[w->n_vectors].name = NULL;
		w->vectors[w->n_vectors].x = NULL;
		w->vectors[w->n_vectors].y = NULL;
		vectors = w->vectors;
	}

	jnl_vtk_write(w->path, w->mesh, scalars, vectors);

	return 0;
}

static int l_writer_gc(lua_State *L)
{
	lua_vtk_writer *w = check_writer(L, 1);

	free(w->scalars);
	free(w->vectors);

	if (w->mesh_ref != LUA_NOREF)
		luaL_unref(L, LUA_REGISTRYINDEX, w->mesh_ref);

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
	// Ensure vec metatable exists for check_vec.
	luaL_requiref(L, "jnl.vec_internal", luaopen_vec_internal, 0);
	lua_pop(L, 1);

	luaL_newmetatable(L, VTK_WRITER_MT);
	luaL_setfuncs(L, writer_methods, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, vtk_funcs);
	return 1;
}
