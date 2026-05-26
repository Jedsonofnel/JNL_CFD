#include <lauxlib.h>
#include <lua.h>
#include <math.h>
#include <string.h>

#include "lua_bindings.h"
#include "jnl/common.h"
#include "mesh2d.h"

#define PSLG_MT "jnl.geo2d.pslg"
#define TAGS_MT "jnl.mesh2d.tri_tags"
#define OPTS_MT "jnl.mesh2d.tri_opts"
#define SPEC_MT "jnl.mesh2d.tri_spec"

//
// Internal helpers
//

static struct jnl_pslg *check_pslg(lua_State *L, int idx)
{
	return (struct jnl_pslg *)luaL_checkudata(L, idx, PSLG_MT);
}

static struct jnl_tri_opts *check_opts(lua_State *L, int idx)
{
	return (struct jnl_tri_opts *)luaL_checkudata(L, idx, OPTS_MT);
}

struct lua_tri_spec {
	struct jnl_tri_opts opts;
	struct jnl_tri_tags tags;
};

static struct lua_tri_spec *check_spec(lua_State *L, int idx)
{
	return (struct lua_tri_spec *)luaL_checkudata(L, idx, SPEC_MT);
}

static struct jnl_tri_tags *check_tags(lua_State *L, int idx)
{
	return (struct jnl_tri_tags *)luaL_checkudata(L, idx, TAGS_MT);
}

static int push_mesh_err(lua_State *L, enum jnl_mesh_err err)
{
	switch (err) {
	case JNL_MESH_OK:
		lua_pushstring(L, "ok");
		break;
	case JNL_MESH_ERR_UNKNOWN_PATCH:
		lua_pushstring(L, "unknown_patch");
		break;
	case JNL_MESH_ERR_UNKNOWN_BAFFLE:
		lua_pushstring(L, "unknown_baffle");
		break;
	case JNL_MESH_ERR_UNKNOWN_REGION:
		lua_pushstring(L, "unknown_region");
		break;
	case JNL_MESH_ERR_ALLOC:
		lua_pushstring(L, "alloc");
		break;
	case JNL_MESH_ERR_INVALID_INPUT:
		lua_pushstring(L, "invalid_input");
		break;
	case JNL_MESH_ERR_TRIANGLE_FAILED:
		lua_pushstring(L, "triangle_failed");
		break;
	case JNL_MESH_ERR_INVALID_BAFFLE:
		lua_pushstring(L, "invalid_baffle");
		break;
	case JNL_MESH_ERR_DUPLICATE_MARKER:
		lua_pushstring(L, "duplicate_marker");
		break;
	default:
		lua_pushstring(L, "unknown_error");
		break;
	}
	return 1;
}

//
// Tri opts
//

// opts_default()
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

static int l_opts_set_min_angle(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	f64 angle = luaL_checknumber(L, 2);
	struct jnl_tri_opts *n = lua_newuserdata(L, sizeof(*n));
	*n = jnl_tri_opts_set_min_angle(*o, angle);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

static int l_opts_set_global_max_area(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	f64 area = luaL_checknumber(L, 2);
	struct jnl_tri_opts *n = lua_newuserdata(L, sizeof(*n));
	*n = jnl_tri_opts_set_global_max_area(*o, area);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

static int l_opts_enable_region_areas(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	bool enabled = lua_toboolean(L, 2);
	struct jnl_tri_opts *n = lua_newuserdata(L, sizeof(*n));
	*n = jnl_tri_opts_enable_region_areas(*o, enabled);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

static int l_opts_set_conforming_delaunay(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	bool enabled = lua_toboolean(L, 2);
	struct jnl_tri_opts *n = lua_newuserdata(L, sizeof(*n));
	*n = jnl_tri_opts_set_conforming_delaunay(*o, enabled);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

static int l_opts_set_quiet(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	bool enabled = lua_toboolean(L, 2);
	struct jnl_tri_opts *n = lua_newuserdata(L, sizeof(*n));
	*n = jnl_tri_opts_set_quiet(*o, enabled);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

// set_cell_count(opts, pslg, n) -> new opts
static int l_opts_set_cell_count(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	struct jnl_pslg *g = check_pslg(L, 2);
	i32 n = (i32)luaL_checkinteger(L, 3);
	struct jnl_tri_opts *r = lua_newuserdata(L, sizeof(*r));
	*r = jnl_tri_opts_set_cell_count(*o, g, n);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

/* set_resolution(opts, pslg, res) -> new opts */
static int l_opts_set_resolution(lua_State *L)
{
	struct jnl_tri_opts *o = check_opts(L, 1);
	struct jnl_pslg *g = check_pslg(L, 2);
	f64 res = luaL_checknumber(L, 3);
	struct jnl_tri_opts *r = lua_newuserdata(L, sizeof(*r));
	*r = jnl_tri_opts_set_resolution(*o, g, res);
	luaL_setmetatable(L, OPTS_MT);
	return 1;
}

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

/* add_patch(tags, marker, name) -> ok, errmsg */
static int l_tags_add_patch(lua_State *L)
{
	struct jnl_tri_tags *t = check_tags(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = luaL_checkstring(L, 3);
	enum jnl_mesh_err e = jnl_tri_tags_add_patch(t, marker, name);
	lua_pushboolean(L, e == JNL_MESH_OK);
	push_mesh_err(L, e);
	return 2;
}

static int l_tags_add_baffle(lua_State *L)
{
	struct jnl_tri_tags *t = check_tags(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = luaL_checkstring(L, 3);
	enum jnl_mesh_err e = jnl_tri_tags_add_baffle(t, marker, name);
	lua_pushboolean(L, e == JNL_MESH_OK);
	push_mesh_err(L, e);
	return 2;
}

static int l_tags_add_region(lua_State *L)
{
	struct jnl_tri_tags *t = check_tags(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = luaL_checkstring(L, 3);
	enum jnl_mesh_err e = jnl_tri_tags_add_region(t, marker, name);
	lua_pushboolean(L, e == JNL_MESH_OK);
	push_mesh_err(L, e);
	return 2;
}

/* find_patch(tags, marker) -> name or nil */
static int l_tags_find_patch(lua_State *L)
{
	struct jnl_tri_tags *t = check_tags(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = jnl_tri_tags_find_patch(t, marker);
	if (name)
		lua_pushstring(L, name);
	else
		lua_pushnil(L);
	return 1;
}

static int l_tags_find_baffle(lua_State *L)
{
	struct jnl_tri_tags *t = check_tags(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = jnl_tri_tags_find_baffle(t, marker);
	if (name)
		lua_pushstring(L, name);
	else
		lua_pushnil(L);
	return 1;
}

static int l_tags_find_region(lua_State *L)
{
	struct jnl_tri_tags *t = check_tags(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = jnl_tri_tags_find_region(t, marker);
	if (name)
		lua_pushstring(L, name);
	else
		lua_pushnil(L);
	return 1;
}

/* require_named_patches(tags, bool) */
static int l_tags_set_require_named_patches(lua_State *L)
{
	check_tags(L, 1)->require_named_patches = lua_toboolean(L, 2);
	return 0;
}

static int l_tags_set_require_named_baffles(lua_State *L)
{
	check_tags(L, 1)->require_named_baffles = lua_toboolean(L, 2);
	return 0;
}

static int l_tags_set_require_named_regions(lua_State *L)
{
	check_tags(L, 1)->require_named_regions = lua_toboolean(L, 2);
	return 0;
}

static const luaL_Reg tags_methods[] = {
    {"add_patch", l_tags_add_patch},
    {"add_baffle", l_tags_add_baffle},
    {"add_region", l_tags_add_region},
    {"find_patch", l_tags_find_patch},
    {"find_baffle", l_tags_find_baffle},
    {"find_region", l_tags_find_region},
    {"set_require_named_patches", l_tags_set_require_named_patches},
    {"set_require_named_baffles", l_tags_set_require_named_baffles},
    {"set_require_named_regions", l_tags_set_require_named_regions},
    {"__gc", l_tags_gc},
    {NULL, NULL},
};

//
// Tri spec
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

/* spec:set_opts(opts) -- copy opts into spec */
static int l_spec_set_opts(lua_State *L)
{
	check_spec(L, 1)->opts = *check_opts(L, 2);
	return 0;
}

/* spec:add_patch / add_baffle / add_region -- delegate to embedded tags */
static int l_spec_add_patch(lua_State *L)
{
	struct lua_tri_spec *s = check_spec(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = luaL_checkstring(L, 3);
	enum jnl_mesh_err e = jnl_tri_tags_add_patch(&s->tags, marker, name);
	lua_pushboolean(L, e == JNL_MESH_OK);
	push_mesh_err(L, e);
	return 2;
}

static int l_spec_add_baffle(lua_State *L)
{
	struct lua_tri_spec *s = check_spec(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = luaL_checkstring(L, 3);
	enum jnl_mesh_err e = jnl_tri_tags_add_baffle(&s->tags, marker, name);
	lua_pushboolean(L, e == JNL_MESH_OK);
	push_mesh_err(L, e);
	return 2;
}

static int l_spec_add_region(lua_State *L)
{
	struct lua_tri_spec *s = check_spec(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);
	const char *name = luaL_checkstring(L, 3);
	enum jnl_mesh_err e = jnl_tri_tags_add_region(&s->tags, marker, name);
	lua_pushboolean(L, e == JNL_MESH_OK);
	push_mesh_err(L, e);
	return 2;
}

static int l_spec_set_require_named_patches(lua_State *L)
{
	check_spec(L, 1)->tags.require_named_patches = lua_toboolean(L, 2);
	return 0;
}

static int l_spec_set_require_named_baffles(lua_State *L)
{
	check_spec(L, 1)->tags.require_named_baffles = lua_toboolean(L, 2);
	return 0;
}

static int l_spec_set_require_named_regions(lua_State *L)
{
	check_spec(L, 1)->tags.require_named_regions = lua_toboolean(L, 2);
	return 0;
}

static const luaL_Reg spec_methods[] = {
    {"set_opts", l_spec_set_opts},
    {"add_patch", l_spec_add_patch},
    {"add_baffle", l_spec_add_baffle},
    {"add_region", l_spec_add_region},
    {"set_require_named_patches", l_spec_set_require_named_patches},
    {"set_require_named_baffles", l_spec_set_require_named_baffles},
    {"set_require_named_regions", l_spec_set_require_named_regions},
    {"__tostring", l_spec_tostring},
    {"__gc", l_spec_gc},
    {NULL, NULL},
};

//
// Triangulation (pslg, spec) -> mesh, errmsg
//

static int l_triangulate(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	struct lua_tri_spec *s = check_spec(L, 2);

	struct jnl_tri_mesh_spec spec;
	spec.opts = s->opts;
	spec.tags = s->tags; /* shallow -- tags owns its own heap */

	struct jnl_mesh *mesh = NULL;
	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(g, &spec, &mesh);

	if (err != JNL_MESH_OK) {
		lua_pushnil(L);
		push_mesh_err(L, err);
		return 2;
	}

	struct jnl_mesh **mp = lua_newuserdata(L, sizeof(*mp));
	*mp = mesh;
	luaL_setmetatable(L, MESH_MT);
	lua_pushstring(L, "ok");
	return 2;
}

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

// Returns patch table: { name, start_face, n_faces, marker }
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
		lua_pushinteger(L, p->data[i].marker);
		lua_setfield(L, -2, "marker");
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

static int l_mesh_cell_vol(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_cells, 2,
	              "cell index out of range");
	lua_pushnumber(L, m->geom.cell_vol[i]);
	return 1;
}

static int l_mesh_mean_cell_size(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);

	// sqrt(total_area / n_cells) = RMS cell size
	f64 total = 0.0;
	for (i32 i = 0; i < m->topo.n_cells; i++)
		total += m->geom.cell_vol[i];
	lua_pushnumber(L, sqrt(total / m->topo.n_cells));
	return 1;
}

//
// Face geometry accessors
//

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

static int l_mesh_face_normal(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < m->topo.n_faces, 2,
	              "face index out of range");
	lua_pushnumber(L, m->geom.face_nx[i]);
	lua_pushnumber(L, m->geom.face_ny[i]);
	return 2;
}

//
// Zero based accessors
//

static int l_mesh_face_owner0(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);

	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");

	lua_pushinteger(L, m->topo.owner[f]);
	return 1;
}

static int l_mesh_face_neighbour0(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);

	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");

	lua_pushinteger(L, m->topo.neighbour[f]);
	return 1;
}

static int l_mesh_face_centre0(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);

	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");

	lua_pushnumber(L, m->geom.face_cx[f]);
	lua_pushnumber(L, m->geom.face_cy[f]);
	return 2;
}

static int l_mesh_face_normal0(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);

	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");

	lua_pushnumber(L, m->geom.face_nx[f]);
	lua_pushnumber(L, m->geom.face_ny[f]);
	return 2;
}

static int l_mesh_face_area0(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	i32 f = (i32)luaL_checkinteger(L, 2);

	luaL_argcheck(L, f >= 0 && f < m->topo.n_faces, 2,
	              "face index out of range");

	lua_pushnumber(L, m->geom.face_area[f]);
	return 1;
}

//
// Bulk accessors
//

static int l_mesh_cell_cx_vec(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	push_owned_vec(L, m->geom.cell_cx, m->topo.n_cells, 1);
	return 1;
}

static int l_mesh_cell_cy_vec(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	push_owned_vec(L, m->geom.cell_cy, m->topo.n_cells, 1);
	return 1;
}

static int l_mesh_cell_vol_vec(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	push_owned_vec(L, m->geom.cell_vol, m->topo.n_cells, 1);
	return 1;
}

static const luaL_Reg mesh2d_methods[] = {
    // key diagnostics
    {"n_cells", l_mesh_n_cells},
    {"n_faces", l_mesh_n_faces},
    {"n_internal_faces", l_mesh_n_internal_faces},
    {"patches", l_mesh_patches},
    {"n_patches", l_mesh_n_patches},
    {"patch_by_name", l_mesh_patch_by_name},
    // 1-indexed cell queries
    {"cell_centre", l_mesh_cell_centre},
    {"cell_vol", l_mesh_cell_vol},
    {"mean_cell_size", l_mesh_mean_cell_size},
    // 1-indexed face queries
    {"face_centre", l_mesh_face_centre},
    {"face_normal", l_mesh_face_normal},
    // 0-indexed face queries
    {"face_owner0", l_mesh_face_owner0},
    {"face_neighbour0", l_mesh_face_neighbour0},
    {"face_centre0", l_mesh_face_centre0},
    {"face_normal0", l_mesh_face_normal0},
    {"face_area0", l_mesh_face_area0},
    // bulk accessors
    {"cell_cx_vec", l_mesh_cell_cx_vec},
    {"cell_cy_vec", l_mesh_cell_cy_vec},
    {"cell_vol_vec", l_mesh_cell_vol_vec},
    {"__tostring", l_mesh_tostring},
    {"__gc", l_mesh_gc},
    {NULL, NULL},
};

//
// Module registration
//

static void register_mt(lua_State *L, const char *name, const luaL_Reg *methods)
{
	luaL_newmetatable(L, name);
	luaL_setfuncs(L, methods, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

static const luaL_Reg mesh2d_funcs[] = {
    {"smesh_gen", l_smesh_gen},     {"opts_default", l_opts_default},
    {"tags_new", l_tags_new},       {"spec_new", l_spec_new},
    {"triangulate", l_triangulate}, {NULL, NULL}};

int luaopen_mesh2d_internal(lua_State *L)
{
	register_mt(L, OPTS_MT, opts_methods);
	register_mt(L, TAGS_MT, tags_methods);
	register_mt(L, SPEC_MT, spec_methods);
	register_mt(L, MESH_MT, mesh2d_methods);

	luaL_newlib(L, mesh2d_funcs);
	return 1;
}
