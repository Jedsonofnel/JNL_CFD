#include <lauxlib.h>
#include <lua.h>
#include <string.h>

#include "lua_bindings.h"
#include "jnl/common.h"
#include "mesh2d/polymesh2d.h"
#include "mesh2d/trimesh2d.h"
#include "geo2d/pslg2d.h"

#define PSLG_MT "jnl.geo2d.pslg"
#define OPTS_MT "jnl.trimesh2d.opts"
#define TAGS_MT "jnl.trimesh2d.tags"
#define SPEC_MT "jnl.trimesh2d.spec"

//
// Userdata checks
//

static struct jnl_pslg *check_pslg(lua_State *L, int idx)
{
	return (struct jnl_pslg *)luaL_checkudata(L, idx, PSLG_MT);
}
static struct jnl_tri_opts *check_opts(lua_State *L, int idx)
{
	return (struct jnl_tri_opts *)luaL_checkudata(L, idx, OPTS_MT);
}
static struct jnl_tri_tags *check_tags(lua_State *L, int idx)
{
	return (struct jnl_tri_tags *)luaL_checkudata(L, idx, TAGS_MT);
}

// Combined spec stored inline in userdata.
struct lua_tri_spec {
	struct jnl_tri_opts opts;
	struct jnl_tri_tags tags;
};

static struct lua_tri_spec *check_spec(lua_State *L, int idx)
{
	return (struct lua_tri_spec *)luaL_checkudata(L, idx, SPEC_MT);
}

// Push a new mesh.  MESH_MT must be registered (guaranteed by luaopen dep).
static void push_mesh(lua_State *L, pmsh2d *mesh)
{
	pmsh2d **mp = lua_newuserdata(L, sizeof(*mp));
	*mp = mesh;
	luaL_setmetatable(L, MESH_MT);
}

// Map jnl_mesh_err to a short Lua string (used for tag operation returns).
static int push_mesh_err(lua_State *L, enum jnl_mesh_err err)
{
	lua_pushstring(L, jnl_mesh_err_str(err));
	return 1;
}

//
// Tri opts — immutable builder pattern (each setter returns a new userdata)
//

static int l_opts_default(lua_State *L)
{
	struct jnl_tri_opts *o = lua_newuserdata(L, sizeof(*o));
	*o = jnl_tri_opts_default();
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

static int l_opts_tostring(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	lua_pushfstring(L, "jnl.tri_opts(min_angle=%.4g, max_area=%.4g)",
	                o->min_angle_deg, o->global_max_area);
	return 1;
}

#define OPTS_SETTER(name, call)                                                \
	static int l_opts_##name(lua_State *L)                                     \
	{                                                                          \
		struct jnl_tri_opts *n = lua_newuserdata(L, sizeof(*n));               \
		*n = call;                                                             \
		luaL_setmetatable(L, OPTS_MT);                                         \
		return 1;                                                              \
	}

OPTS_SETTER(set_min_angle, jnl_tri_opts_set_min_angle(*check_opts(L, 1),
                                                      luaL_checknumber(L, 2)))

OPTS_SETTER(set_global_max_area,
            jnl_tri_opts_set_global_max_area(*check_opts(L, 1),
                                             luaL_checknumber(L, 2)))

OPTS_SETTER(enable_region_areas,
            jnl_tri_opts_enable_region_areas(*check_opts(L, 1),
                                             lua_toboolean(L, 2)))

OPTS_SETTER(set_conforming_delaunay,
            jnl_tri_opts_set_conforming_delaunay(*check_opts(L, 1),
                                                 lua_toboolean(L, 2)))

OPTS_SETTER(set_quiet,
            jnl_tri_opts_set_quiet(*check_opts(L, 1), lua_toboolean(L, 2)))

OPTS_SETTER(set_cell_count,
            jnl_tri_opts_set_cell_count(*check_opts(L, 1), check_pslg(L, 2),
                                        (i32)luaL_checkinteger(L, 3)))

OPTS_SETTER(set_resolution,
            jnl_tri_opts_set_resolution(*check_opts(L, 1), check_pslg(L, 2),
                                        luaL_checknumber(L, 3)))

#undef OPTS_SETTER

static const luaL_Reg opts_methods[] = {
    {"set_min_angle", l_opts_set_min_angle},
    {"set_global_max_area", l_opts_set_global_max_area},
    {"enable_region_areas", l_opts_enable_region_areas},
    {"set_conforming_delaunay", l_opts_set_conforming_delaunay},
    {"set_quiet", l_opts_set_quiet},
    {"set_cell_count", l_opts_set_cell_count},
    {"set_resolution", l_opts_set_resolution},
    {"__tostring", l_opts_tostring},
    {NULL, NULL},
};

//
// Tri tags
//

static int l_tags_new(lua_State *L)
{
	struct jnl_tri_tags *t = lua_newuserdata(L, sizeof(*t));
	jnl_tri_tags_init(t);
	luaL_setmetatable(L, TAGS_MT);
	return 1;
}

static int l_tags_gc(lua_State *L)
{
	jnl_tri_tags_free(check_tags(L, 1));
	return 0;
}

// Returns: ok (bool), errmsg
#define TAGS_ADD(kind)                                                         \
	static int l_tags_add_##kind(lua_State *L)                                 \
	{                                                                          \
		struct jnl_tri_tags *t = check_tags(L, 1);                             \
		i32 marker = (i32)luaL_checkinteger(L, 2);                             \
		const char *name = luaL_checkstring(L, 3);                             \
		enum jnl_mesh_err e = jnl_tri_tags_add_##kind(t, marker, name);        \
		lua_pushboolean(L, e == JNL_MESH_OK);                                  \
		push_mesh_err(L, e);                                                   \
		return 2;                                                              \
	}

TAGS_ADD(patch)
TAGS_ADD(baffle)
TAGS_ADD(region)

#undef TAGS_ADD

#define TAGS_FIND(kind)                                                        \
	static int l_tags_find_##kind(lua_State *L)                                \
	{                                                                          \
		const char *name = jnl_tri_tags_find_##kind(                           \
		    check_tags(L, 1), (i32)luaL_checkinteger(L, 2));                   \
		if (name)                                                              \
			lua_pushstring(L, name);                                           \
		else                                                                   \
			lua_pushnil(L);                                                    \
		return 1;                                                              \
	}

TAGS_FIND(patch)
TAGS_FIND(baffle)
TAGS_FIND(region)

#undef TAGS_FIND

static const luaL_Reg tags_methods[] = {
    {"add_patch", l_tags_add_patch},
    {"add_baffle", l_tags_add_baffle},
    {"add_region", l_tags_add_region},
    {"find_patch", l_tags_find_patch},
    {"find_baffle", l_tags_find_baffle},
    {"find_region", l_tags_find_region},
    {"__gc", l_tags_gc},
    {NULL, NULL},
};

//
// Tri spec — opts + tags bundled
//

static int l_spec_new(lua_State *L)
{
	struct lua_tri_spec *s = lua_newuserdata(L, sizeof(*s));
	s->opts = jnl_tri_opts_default();
	jnl_tri_tags_init(&s->tags);
	luaL_setmetatable(L, SPEC_MT);
	return 1;
}

static int l_spec_gc(lua_State *L)
{
	jnl_tri_tags_free(&check_spec(L, 1)->tags);
	return 0;
}

static int l_spec_tostring(lua_State *L)
{
	struct lua_tri_spec *s = check_spec(L, 1);
	lua_pushfstring(L, "jnl.tri_spec(min_angle=%.4g)", s->opts.min_angle_deg);
	return 1;
}

static int l_spec_set_opts(lua_State *L)
{
	check_spec(L, 1)->opts = *check_opts(L, 2);
	return 0;
}

#define SPEC_ADD(kind)                                                         \
	static int l_spec_add_##kind(lua_State *L)                                 \
	{                                                                          \
		struct lua_tri_spec *s = check_spec(L, 1);                             \
		i32 marker = (i32)luaL_checkinteger(L, 2);                             \
		const char *name = luaL_checkstring(L, 3);                             \
		enum jnl_mesh_err e = jnl_tri_tags_add_##kind(&s->tags, marker, name); \
		lua_pushboolean(L, e == JNL_MESH_OK);                                  \
		push_mesh_err(L, e);                                                   \
		return 2;                                                              \
	}

SPEC_ADD(patch)
SPEC_ADD(baffle)
SPEC_ADD(region)

#undef SPEC_ADD

static const luaL_Reg spec_methods[] = {
    {"set_opts", l_spec_set_opts},
    {"add_patch", l_spec_add_patch},
    {"add_baffle", l_spec_add_baffle},
    {"add_region", l_spec_add_region},
    {"__tostring", l_spec_tostring},
    {"__gc", l_spec_gc},
    {NULL, NULL},
};

//
// triangulate(pslg, spec) -> mesh, nil | nil, errmsg
//

static int l_triangulate(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	struct lua_tri_spec *s = check_spec(L, 2);

	struct jnl_tri_mesh_spec spec = {.opts = s->opts, .tags = s->tags};

	pmsh2d *mesh = NULL;
	enum jnl_mesh_err err = jnl_trimesh2d_from_pslg(g, &spec, &mesh);
	if (err != JNL_MESH_OK) {
		lua_pushnil(L);
		push_mesh_err(L, err);
		return 2;
	}
	push_mesh(L, mesh);
	lua_pushnil(L);
	return 2;
}

//
// Module
//

static const luaL_Reg trimesh2d_funcs[] = {
    {"opts_default", l_opts_default},
    {"tags_new", l_tags_new},
    {"spec_new", l_spec_new},
    {"triangulate", l_triangulate},
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

int luaopen_trimesh2d_internal(lua_State *L)
{
	// Ensure MESH_MT is registered before triangulate can push meshes.
	luaL_requiref(L, "jnl.mesh2d_internal", luaopen_mesh2d_internal, 0);
	lua_pop(L, 1);

	register_mt(L, OPTS_MT, opts_methods);
	register_mt(L, TAGS_MT, tags_methods);
	register_mt(L, SPEC_MT, spec_methods);

	luaL_newlib(L, trimesh2d_funcs);
	return 1;
}
