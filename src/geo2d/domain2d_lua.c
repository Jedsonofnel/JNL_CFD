#include <stdlib.h>
#include <string.h>

#include "lua_bindings.h"
#include "geo2d/domain2d.h"

//
// Userdata helpers
//

static struct jnl_domain2d *check_domain2d(lua_State *L, int idx)
{
	return (struct jnl_domain2d *)luaL_checkudata(L, idx, DOMAIN2D_MT);
}

static struct jnl_domain2d *push_domain2d(lua_State *L)
{
	struct jnl_domain2d *d =
	    (struct jnl_domain2d *)lua_newuserdatauv(L, sizeof(*d), 1);
	memset(d, 0, sizeof(*d));
	luaL_setmetatable(L, DOMAIN2D_MT);
	return d;
}

// Reused from curve2d_lua.c in spirit.
// TODO: extract to geo2d/lua_helpers.h when there are three users.
static jnl_vec2d check_point(lua_State *L, int idx)
{
	idx = lua_absindex(L, idx);
	luaL_checktype(L, idx, LUA_TTABLE);
	lua_geti(L, idx, 1);
	f64 x = luaL_checknumber(L, -1);
	lua_pop(L, 1);
	lua_geti(L, idx, 2);
	f64 y = luaL_checknumber(L, -1);
	lua_pop(L, 1);
	return (jnl_vec2d){.x = x, .y = y};
}

static void push_point(lua_State *L, jnl_vec2d p)
{
	lua_createtable(L, 2, 0);
	lua_pushnumber(L, p.x);
	lua_seti(L, -2, 1);
	lua_pushnumber(L, p.y);
	lua_seti(L, -2, 2);
}

static void push_points(lua_State *L, const jnl_vec2d *pts, i32 n)
{
	lua_createtable(L, n, 0);
	for (i32 i = 0; i < n; i++) {
		push_point(L, pts[i]);
		lua_seti(L, -2, i + 1);
	}
}

static struct jnl_curve2d *check_curve2d_arg(lua_State *L, int idx)
{
	return (struct jnl_curve2d *)luaL_checkudata(L, idx, CURVE2D_MT);
}

static int domain_error(lua_State *L, const char *op, enum jnl_domain2d_err err)
{
	return luaL_error(L, "%s failed: %s", op, jnl_domain2d_err_str(err));
}

//
// Constructor
//

// domain2d_internal.new(outer_curve) -> domain
static int l_domain_new(lua_State *L)
{
	struct jnl_curve2d *outer = check_curve2d_arg(L, 1);
	struct jnl_domain2d *d = push_domain2d(L);

	enum jnl_domain2d_err err = jnl_domain2d_init(d, outer);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "domain2d.new", err);

	return 1;
}

//
// Lifecycle
//

static int l_domain_gc(lua_State *L)
{
	jnl_domain2d_free(check_domain2d(L, 1));
	return 0;
}

static int l_domain_tostring(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	lua_pushfstring(L, "domain2d(patches=%d, holes=%d, regions=%d)",
	                d->n_patches, d->n_holes, d->n_regions);
	return 1;
}

//
// Construction methods — all return self for chaining
//

// domain:add_patch(name, marker, curve) -> self
static int l_domain_add_patch(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	const char *name = luaL_checkstring(L, 2);
	i32 marker = (i32)luaL_checkinteger(L, 3);
	struct jnl_curve2d *curve = check_curve2d_arg(L, 4);

	enum jnl_domain2d_err err = jnl_domain2d_add_patch(d, name, marker, curve);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "add_patch", err);

	lua_settop(L, 1);
	return 1;
}

// domain:add_hole(name_or_nil, marker, boundary_curve, seed) -> self
// seed: {x, y}
static int l_domain_add_hole(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	const char *name = lua_isnoneornil(L, 2) ? NULL : luaL_checkstring(L, 2);
	i32 marker = (i32)luaL_checkinteger(L, 3);
	struct jnl_curve2d *boundary = check_curve2d_arg(L, 4);
	jnl_vec2d seed = check_point(L, 5);

	enum jnl_domain2d_err err =
	    jnl_domain2d_add_hole(d, name, marker, boundary, seed);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "add_hole", err);

	lua_settop(L, 1);
	return 1;
}

// domain:add_region(name, marker, seed, max_area?) -> self
// seed: {x, y}; max_area defaults to -1 (unconstrained)
static int l_domain_add_region(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	const char *name = luaL_checkstring(L, 2);
	i32 marker = (i32)luaL_checkinteger(L, 3);
	jnl_vec2d seed = check_point(L, 4);
	f64 max_area = luaL_optnumber(L, 5, -1.0);

	enum jnl_domain2d_err err =
	    jnl_domain2d_add_region(d, name, marker, seed, max_area);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "add_region", err);

	lua_settop(L, 1);
	return 1;
}

// domain:set_default_marker(marker) -> self
static int l_domain_set_default_marker(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	i32 marker = (i32)luaL_checkinteger(L, 2);

	jnl_domain2d_set_default_marker(d, marker);

	lua_settop(L, 1);
	return 1;
}

//
// Validation
//

// domain:check() -> true | nil, msg
static int l_domain_check(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);

	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(d, &msg);

	if (err == JNL_DOMAIN2D_OK) {
		lua_pushboolean(L, 1);
		return 1;
	}

	lua_pushnil(L);
	lua_pushstring(L, msg ? msg : jnl_domain2d_err_str(err));
	return 2;
}

//
// Queries
//

// domain:contains(point, sample_n?) -> bool
static int l_domain_contains(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	jnl_vec2d p = check_point(L, 2);
	i32 sample_n = (i32)luaL_optinteger(L, 3, 128);

	lua_pushboolean(L, jnl_domain2d_contains(d, p, sample_n));
	return 1;
}

// domain:curve_intersects_boundary(curve, sample_n?) -> bool
static int l_domain_curve_intersects_boundary(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	struct jnl_curve2d *c = check_curve2d_arg(L, 2);
	i32 sample_n = (i32)luaL_optinteger(L, 3, 128);

	lua_pushboolean(L, jnl_domain2d_curve_intersects_boundary(d, c, sample_n));
	return 1;
}

// domain:outer_self_intersects(sample_n?) -> bool
static int l_domain_outer_self_intersects(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	i32 sample_n = (i32)luaL_optinteger(L, 2, 128);

	lua_pushboolean(L, jnl_domain2d_outer_self_intersects(d, sample_n));
	return 1;
}

// domain:holes_intersect(i, j, sample_n?) -> bool
// i, j: 1-based
static int l_domain_holes_intersect(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	i32 j = (i32)luaL_checkinteger(L, 3) - 1;
	i32 sample_n = (i32)luaL_optinteger(L, 4, 128);

	lua_pushboolean(L, jnl_domain2d_holes_intersect(d, i, j, sample_n));
	return 1;
}

//
// Bounding box
//

// domain:bbox() -> {min_x=, min_y=, max_x=, max_y=}
static int l_domain_bbox(lua_State *L)
{
	struct jnl_aabb bb = jnl_domain2d_bbox(check_domain2d(L, 1));

	lua_createtable(L, 0, 4);
	lua_pushnumber(L, bb.min_x);
	lua_setfield(L, -2, "min_x");
	lua_pushnumber(L, bb.min_y);
	lua_setfield(L, -2, "min_y");
	lua_pushnumber(L, bb.max_x);
	lua_setfield(L, -2, "max_x");
	lua_pushnumber(L, bb.max_y);
	lua_setfield(L, -2, "max_y");

	return 1;
}

//
// Sampling
//

// domain:sample_outer(n) -> {{x,y}, ...}
static int l_domain_sample_outer(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	i32 n = (i32)luaL_checkinteger(L, 2);

	if (n < 2)
		return luaL_error(L, "sample count must be >= 2");

	jnl_vec2d *pts = NULL;
	i32 out_n = 0;
	enum jnl_domain2d_err err = jnl_domain2d_sample_outer(d, n, &pts, &out_n);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "sample_outer", err);

	push_points(L, pts, out_n);
	free(pts);
	return 1;
}

// domain:sample_hole(i, n) -> {{x,y}, ...}
// i: 1-based
static int l_domain_sample_hole(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	i32 hole_idx = (i32)luaL_checkinteger(L, 2) - 1;
	i32 n = (i32)luaL_checkinteger(L, 3);

	if (n < 2)
		return luaL_error(L, "sample count must be >= 2");

	jnl_vec2d *pts = NULL;
	i32 out_n = 0;
	enum jnl_domain2d_err err =
	    jnl_domain2d_sample_hole(d, hole_idx, n, &pts, &out_n);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "sample_hole", err);

	push_points(L, pts, out_n);
	free(pts);
	return 1;
}

// domain:sample_all(n) -> { {pts={{x,y},...}, marker=m, name="..."}, ... }
//
// Index 1 is always the outer boundary (name = "").
// Indices 2..n_holes+1 are hole boundaries.
// Indices n_holes+2.. are patch curves.
static int l_domain_sample_all(lua_State *L)
{
	struct jnl_domain2d *d = check_domain2d(L, 1);
	i32 n = (i32)luaL_checkinteger(L, 2);

	if (n < 2)
		return luaL_error(L, "sample count must be >= 2");

	struct jnl_domain2d_sample_result *results = NULL;
	i32 count = 0;
	enum jnl_domain2d_err err = jnl_domain2d_sample_all(d, n, &results, &count);
	if (err != JNL_DOMAIN2D_OK)
		return domain_error(L, "sample_all", err);

	lua_createtable(L, count, 0);

	for (i32 i = 0; i < count; i++) {
		lua_createtable(L, 0, 3);

		push_points(L, results[i].pts, results[i].n);
		lua_setfield(L, -2, "pts");

		lua_pushinteger(L, results[i].marker);
		lua_setfield(L, -2, "marker");

		lua_pushstring(L, results[i].name);
		lua_setfield(L, -2, "name");

		lua_seti(L, -2, i + 1);
	}

	jnl_domain2d_sample_results_free(results, count);
	return 1;
}

//
// Indexing metamethods
//

static int l_domain_newindex(lua_State *L)
{
	// store in a per-instance table kept as the first uservalue
	if (lua_getiuservalue(L, 1, 1) != LUA_TTABLE) {
		lua_pop(L, 1);
		lua_newtable(L);
		lua_pushvalue(L, -1);
		lua_setiuservalue(L, 1, 1);
	}
	lua_pushvalue(L, 2);
	lua_pushvalue(L, 3);
	lua_rawset(L, -3);
	return 0;
}

static int l_domain_index(lua_State *L)
{
	// methods first
	if (luaL_getmetafield(L, 1, lua_tostring(L, 2)) != LUA_TNIL)
		return 1;
	// then per-instance table
	if (lua_getiuservalue(L, 1, 1) == LUA_TTABLE) {
		lua_pushvalue(L, 2);
		lua_rawget(L, -2);
		return 1;
	}
	lua_pushnil(L);
	return 1;
}

//
// Accessors
//

static int l_domain_n_patches(lua_State *L)
{
	lua_pushinteger(L, check_domain2d(L, 1)->n_patches);
	return 1;
}

static int l_domain_n_holes(lua_State *L)
{
	lua_pushinteger(L, check_domain2d(L, 1)->n_holes);
	return 1;
}

static int l_domain_n_regions(lua_State *L)
{
	lua_pushinteger(L, check_domain2d(L, 1)->n_regions);
	return 1;
}

//
// Registration
//

static const luaL_Reg domain_methods[] = {
    // Construction
    {"add_patch", l_domain_add_patch},
    {"add_hole", l_domain_add_hole},
    {"add_region", l_domain_add_region},
    {"set_default_marker", l_domain_set_default_marker},
    // Validation
    {"check", l_domain_check},
    // Queries
    {"contains", l_domain_contains},
    {"curve_intersects_boundary", l_domain_curve_intersects_boundary},
    {"outer_self_intersects", l_domain_outer_self_intersects},
    {"holes_intersect", l_domain_holes_intersect},
    // Geometry
    {"bbox", l_domain_bbox},
    // Sampling
    {"sample_outer", l_domain_sample_outer},
    {"sample_hole", l_domain_sample_hole},
    {"sample_all", l_domain_sample_all},
    // Accessors
    {"n_patches", l_domain_n_patches},
    {"n_holes", l_domain_n_holes},
    {"n_regions", l_domain_n_regions},
    // Metamethods
    {"__tostring", l_domain_tostring},
    {"__gc", l_domain_gc},
    {"__index", l_domain_index},
    {"__newindex", l_domain_newindex},
    {NULL, NULL},
};

static const luaL_Reg domain2d_funcs[] = {
    {"new", l_domain_new},
    {NULL, NULL},
};

int luaopen_domain2d_internal(lua_State *L)
{
    luaL_newmetatable(L, DOMAIN2D_MT);
    luaL_setfuncs(L, domain_methods, 0);
    lua_pop(L, 1);

    luaL_newlib(L, domain2d_funcs);
    return 1;
}
