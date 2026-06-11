#include <stdlib.h>
#include <string.h>

#include "lua_bindings.h"
#include "geo2d/curve2d.h"

//
// Userdata helpers
//

static struct jnl_curve2d *check_curve2d(lua_State *L, int idx)
{
	return (struct jnl_curve2d *)luaL_checkudata(L, idx, CURVE2D_MT);
}

static struct jnl_dist1d *check_dist1d(lua_State *L, int idx)
{
	return (struct jnl_dist1d *)luaL_checkudata(L, idx, DIST1D_MT);
}

static struct jnl_curve2d *push_curve2d(lua_State *L)
{
	struct jnl_curve2d *c =
	    (struct jnl_curve2d *)lua_newuserdata(L, sizeof(*c));

	/*
	 * Initialise to a harmless value curve so __gc is always safe,
	 * including when a constructor fails and luaL_error() unwinds.
	 */
	*c = jnl_curve2d_line_xy(0.0, 0.0, 0.0, 0.0);

	luaL_setmetatable(L, CURVE2D_MT);
	return c;
}

static struct jnl_dist1d *push_dist1d(lua_State *L, struct jnl_dist1d dist)
{
	struct jnl_dist1d *d = (struct jnl_dist1d *)lua_newuserdata(L, sizeof(*d));

	*d = dist;
	luaL_setmetatable(L, DIST1D_MT);

	return d;
}

static int curve_error(lua_State *L, const char *operation,
                       enum jnl_curve2d_err err)
{
	return luaL_error(L, "%s failed: %s", operation, jnl_curve2d_err_str(err));
}

//
// Point marshalling
//

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

	jnl_vec2d p = {
	    .x = x,
	    .y = y,
	};

	return p;
}

static void push_point(lua_State *L, jnl_vec2d p)
{
	lua_createtable(L, 2, 0);

	lua_pushnumber(L, p.x);
	lua_seti(L, -2, 1);

	lua_pushnumber(L, p.y);
	lua_seti(L, -2, 2);
}

//
// Curve metadata
//

static const char *curve_kind_str(enum jnl_curve2d_kind kind)
{
	switch (kind) {
	case JNL_CURVE2D_LINE:
		return "line";
	case JNL_CURVE2D_ARC:
		return "arc";
	case JNL_CURVE2D_POLYLINE:
		return "polyline";
	case JNL_CURVE2D_CHAIN:
		return "chain";
	default:
		return "unknown";
	}
}

static const char *dist_kind_str(enum jnl_dist1d_kind kind)
{
	switch (kind) {
	case JNL_DIST1D_UNIFORM:
		return "uniform";
	case JNL_DIST1D_COSINE_BOTH:
		return "cosine_both";
	case JNL_DIST1D_GEOM_START:
		return "geom_start";
	case JNL_DIST1D_GEOM_END:
		return "geom_end";
	default:
		return "unknown";
	}
}

//
// Curve constructors
//

// curve.line(x0, y0, x1, y1) -> curve
static int l_curve_line(lua_State *L)
{
	f64 x0 = luaL_checknumber(L, 1);
	f64 y0 = luaL_checknumber(L, 2);
	f64 x1 = luaL_checknumber(L, 3);
	f64 y1 = luaL_checknumber(L, 4);

	struct jnl_curve2d *c = push_curve2d(L);
	*c = jnl_curve2d_line_xy(x0, y0, x1, y1);

	enum jnl_curve2d_err err = jnl_curve2d_check(c);
	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "line construction", err);

	return 1;
}

// curve.arc(cx, cy, radius, theta0, theta1) -> curve
static int l_curve_arc(lua_State *L)
{
	f64 cx = luaL_checknumber(L, 1);
	f64 cy = luaL_checknumber(L, 2);
	f64 radius = luaL_checknumber(L, 3);
	f64 theta0 = luaL_checknumber(L, 4);
	f64 theta1 = luaL_checknumber(L, 5);

	struct jnl_curve2d *c = push_curve2d(L);
	*c = jnl_curve2d_arc_xy(cx, cy, radius, theta0, theta1);

	enum jnl_curve2d_err err = jnl_curve2d_check(c);
	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "arc construction", err);

	return 1;
}

// curve.polyline({{x0, y0}, {x1, y1}, ...}) -> curve
static int l_curve_polyline(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);

	size_t raw_n = lua_rawlen(L, 1);
	if (raw_n < 2 || raw_n > INT32_MAX)
		return luaL_error(L, "polyline requires at least two points");

	i32 n = (i32)raw_n;

	jnl_vec2d *points = malloc((size_t)n * sizeof(*points));
	if (!points)
		return luaL_error(L, "polyline allocation failed");

	for (i32 i = 0; i < n; ++i) {
		lua_geti(L, 1, i + 1);
		points[i] = check_point(L, -1);
		lua_pop(L, 1);
	}

	struct jnl_curve2d *c = push_curve2d(L);
	enum jnl_curve2d_err err = jnl_curve2d_polyline(c, points, n);

	free(points);

	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "polyline construction", err);

	return 1;
}

// curve.chain({curve0, curve1, ...}) -> curve
static int l_curve_chain(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);

	size_t raw_n = lua_rawlen(L, 1);
	if (raw_n < 1 || raw_n > INT32_MAX)
		return luaL_error(L, "chain requires at least one curve");

	i32 n = (i32)raw_n;

	/*
	 * These are temporary shallow copies only. jnl_curve2d_chain()
	 * deep-clones each child before this array is released.
	 */
	struct jnl_curve2d *curves = malloc((size_t)n * sizeof(*curves));

	if (!curves)
		return luaL_error(L, "chain allocation failed");

	for (i32 i = 0; i < n; ++i) {
		lua_geti(L, 1, i + 1);
		curves[i] = *check_curve2d(L, -1);
		lua_pop(L, 1);
	}

	struct jnl_curve2d *c = push_curve2d(L);
	enum jnl_curve2d_err err = jnl_curve2d_chain(c, curves, n);

	/*
	 * Do not call jnl_curve2d_free() on these temporary shallow copies.
	 * Their owned allocations belong to the original Lua userdata.
	 */
	free(curves);

	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "chain construction", err);

	return 1;
}

//
// Curve lifecycle / representation
//

static int l_curve_gc(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	jnl_curve2d_free(c);
	return 0;
}

static int l_curve_tostring(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);

	lua_pushfstring(L, "curve2d(%s, length=%f%s)", curve_kind_str(c->kind),
	                jnl_curve2d_length(c), c->reversed ? ", reversed" : "");

	return 1;
}

static int l_curve_kind(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	lua_pushstring(L, curve_kind_str(c->kind));
	return 1;
}

static int l_curve_clone(lua_State *L)
{
	struct jnl_curve2d *src = check_curve2d(L, 1);
	struct jnl_curve2d *out = push_curve2d(L);

	enum jnl_curve2d_err err = jnl_curve2d_clone(out, src);
	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "curve clone", err);

	return 1;
}

static int l_curve_reversed(lua_State *L)
{
	struct jnl_curve2d *src = check_curve2d(L, 1);
	struct jnl_curve2d *out = push_curve2d(L);

	enum jnl_curve2d_err err = jnl_curve2d_reversed(out, src);
	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "curve reversal", err);

	return 1;
}

static int l_curve_reverse_inplace(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	jnl_curve2d_reverse_inplace(c);

	lua_settop(L, 1);
	return 1;
}

//
// Curve evaluation
//

static int l_curve_length(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	lua_pushnumber(L, jnl_curve2d_length(c));
	return 1;
}

static int l_curve_start(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	push_point(L, jnl_curve2d_start(c));
	return 1;
}

static int l_curve_end(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	push_point(L, jnl_curve2d_end(c));
	return 1;
}

// curve:eval(t) -> {x, y}
static int l_curve_eval(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	f64 t = luaL_checknumber(L, 2);

	push_point(L, jnl_curve2d_eval(c, t));
	return 1;
}

// curve:eval_arclen(s) -> {x, y}
static int l_curve_eval_arclen(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);
	f64 s = luaL_checknumber(L, 2);

	push_point(L, jnl_curve2d_eval_arclen(c, s));
	return 1;
}

// curve:sample(n [, distribution [, mode]]) -> {{x, y}, ...}
//
// mode:
//   "arclen" -- default
//   "param"
static int l_curve_sample(lua_State *L)
{
	struct jnl_curve2d *c = check_curve2d(L, 1);

	lua_Integer lua_n = luaL_checkinteger(L, 2);
	if (lua_n < 1 || lua_n > INT32_MAX)
		return luaL_error(L, "sample count must be a positive integer");

	i32 n = (i32)lua_n;

	struct jnl_dist1d uniform = jnl_dist1d_uniform();
	const struct jnl_dist1d *dist = &uniform;

	if (!lua_isnoneornil(L, 3))
		dist = check_dist1d(L, 3);

	const char *mode_name = luaL_optstring(L, 4, "arclen");
	enum jnl_curve2d_sample_mode mode;

	if (strcmp(mode_name, "arclen") == 0) {
		mode = JNL_CURVE2D_SAMPLE_ARCLEN;
	} else if (strcmp(mode_name, "param") == 0) {
		mode = JNL_CURVE2D_SAMPLE_PARAM;
	} else {
		return luaL_error(L,
		                  "unknown sampling mode '%s'; expected "
		                  "'arclen' or 'param'",
		                  mode_name);
	}

	jnl_vec2d *points = malloc((size_t)n * sizeof(*points));
	if (!points)
		return luaL_error(L, "sample allocation failed");

	enum jnl_curve2d_err err = jnl_curve2d_sample(c, n, dist, mode, points);

	if (err != JNL_CURVE2D_OK) {
		free(points);
		return curve_error(L, "curve sampling", err);
	}

	lua_createtable(L, n, 0);

	for (i32 i = 0; i < n; ++i) {
		push_point(L, points[i]);
		lua_seti(L, -2, i + 1);
	}

	free(points);
	return 1;
}

//
// Distribution constructors
//

// curve.uniform() -> distribution
static int l_dist_uniform(lua_State *L)
{
	(void)L;
	push_dist1d(L, jnl_dist1d_uniform());
	return 1;
}

// curve.cosine_both() -> distribution
static int l_dist_cosine_both(lua_State *L)
{
	(void)L;
	push_dist1d(L, jnl_dist1d_cosine_both());
	return 1;
}

// curve.geom_start(ratio) -> distribution
static int l_dist_geom_start(lua_State *L)
{
	f64 ratio = luaL_checknumber(L, 1);
	struct jnl_dist1d *d = push_dist1d(L, jnl_dist1d_geom_start(ratio));

	enum jnl_curve2d_err err = jnl_dist1d_check(d);
	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "geometric distribution", err);

	return 1;
}

// curve.geom_end(ratio) -> distribution
static int l_dist_geom_end(lua_State *L)
{
	f64 ratio = luaL_checknumber(L, 1);
	struct jnl_dist1d *d = push_dist1d(L, jnl_dist1d_geom_end(ratio));

	enum jnl_curve2d_err err = jnl_dist1d_check(d);
	if (err != JNL_CURVE2D_OK)
		return curve_error(L, "geometric distribution", err);

	return 1;
}

static int l_dist_tostring(lua_State *L)
{
	struct jnl_dist1d *d = check_dist1d(L, 1);

	switch (d->kind) {
	case JNL_DIST1D_GEOM_START:
	case JNL_DIST1D_GEOM_END:
		lua_pushfstring(L, "dist1d(%s, ratio=%f)", dist_kind_str(d->kind),
		                d->ratio);
		break;

	default:
		lua_pushfstring(L, "dist1d(%s)", dist_kind_str(d->kind));
		break;
	}

	return 1;
}

static int l_dist_kind(lua_State *L)
{
	struct jnl_dist1d *d = check_dist1d(L, 1);
	lua_pushstring(L, dist_kind_str(d->kind));
	return 1;
}

static int l_dist_eval(lua_State *L)
{
	struct jnl_dist1d *d = check_dist1d(L, 1);
	lua_Integer i = luaL_checkinteger(L, 2);
	lua_Integer n = luaL_checkinteger(L, 3);

	if (n < 1 || n > INT32_MAX || i < 0 || i >= n)
		return luaL_error(L, "expected 0 <= i < n");

	lua_pushnumber(L, jnl_dist1d_eval(d, (i32)i, (i32)n));
	return 1;
}

//
// Registration
//

static const luaL_Reg curve_methods[] = {
    {"kind", l_curve_kind},
    {"clone", l_curve_clone},
    {"reversed", l_curve_reversed},
    {"reverse_inplace", l_curve_reverse_inplace},

    {"length", l_curve_length},
    {"start", l_curve_start},
    {"finish", l_curve_end},
    {"eval", l_curve_eval},
    {"eval_arclen", l_curve_eval_arclen},
    {"sample", l_curve_sample},

    {"__tostring", l_curve_tostring},
    {"__gc", l_curve_gc},
    {NULL, NULL},
};

static const luaL_Reg dist_methods[] = {
    {"kind", l_dist_kind},
    {"eval", l_dist_eval},

    {"__tostring", l_dist_tostring},
    {NULL, NULL},
};

static const luaL_Reg curve2d_funcs[] = {
    {"line", l_curve_line},
    {"arc", l_curve_arc},
    {"polyline", l_curve_polyline},
    {"chain", l_curve_chain},

    {"uniform", l_dist_uniform},
    {"cosine_both", l_dist_cosine_both},
    {"geom_start", l_dist_geom_start},
    {"geom_end", l_dist_geom_end},

    {NULL, NULL},
};

int luaopen_curve2d_internal(lua_State *L)
{
	luaL_newmetatable(L, CURVE2D_MT);
	luaL_setfuncs(L, curve_methods, 0);

	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	lua_pop(L, 1);

	luaL_newmetatable(L, DIST1D_MT);
	luaL_setfuncs(L, dist_methods, 0);

	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	lua_pop(L, 1);

	luaL_newlib(L, curve2d_funcs);
	return 1;
}
