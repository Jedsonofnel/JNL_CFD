#include "lua_bindings.h"
#include "geo2d.h"

//
// PSLG API
//

// Get a pslg userdata from the stack, with type checking
static struct jnl_pslg *check_pslg(lua_State *L, int idx)
{
	return (struct jnl_pslg *)luaL_checkudata(L, idx, PSLG_MT);
}

// pslg.new() -> pslg userdata
static int l_pslg_new(lua_State *L)
{
	struct jnl_pslg *g = lua_newuserdata(L, sizeof(struct jnl_pslg));
	jnl_pslg_init(g);
	luaL_setmetatable(L, PSLG_MT);
	return 1;
}

// pslg:__gc()
static int l_pslg_gc(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	jnl_pslg_free(g);
	return 0;
}

static int l_pslg_tostring(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	lua_pushfstring(L, "pslg(nodes=%d, edges=%d)", g->nodes.len, g->edges.len);
	return 1;
}

// pslg:node_add(x, y, marker) -> index
static int l_pslg_node_add(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	f64 x = luaL_checknumber(L, 2);
	f64 y = luaL_checknumber(L, 3);
	i32 marker = (i32)luaL_optinteger(L, 4, 0);
	u32 idx = jnl_pslg_node_add(g, x, y, marker);
	lua_pushinteger(L, idx);
	return 1;
}

// pslg:node_get(index) -> x, y  (nil if oob)
static int l_pslg_node_get(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	u32 idx = (u32)luaL_checkinteger(L, 2);
	jnl_vec2d v;
	if (jnl_pslg_node_get(g, idx, &v) != GEO_OK) {
		lua_pushnil(L);
		return 1;
	}
	lua_pushnumber(L, v.x);
	lua_pushnumber(L, v.y);
	return 2;
}

// pslg:node_find_nearest(x, y) -> index or nil
static int l_pslg_node_find_nearest(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	f64 x = luaL_checknumber(L, 2);
	f64 y = luaL_checknumber(L, 3);
	i32 idx = jnl_pslg_node_find_nearest(g, x, y);
	if (idx == GEO_NOT_FOUND) {
		lua_pushnil(L);
		return 1;
	}
	lua_pushinteger(L, idx);
	return 1;
}

// pslg:node_find_or_add(x, y, marker, eps) -> index
static int l_pslg_node_find_or_add(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	f64 x = luaL_checknumber(L, 2);
	f64 y = luaL_checknumber(L, 3);
	i32 marker = (i32)luaL_optinteger(L, 4, 0);
	f64 eps = luaL_optnumber(L, 5, 1e-10);
	lua_pushinteger(L, jnl_pslg_node_find_or_add(g, x, y, marker, eps));
	return 1;
}

// pslg:edge_add(p, q, marker) -> index
static int l_pslg_edge_add(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	u32 p = (u32)luaL_checkinteger(L, 2);
	u32 q = (u32)luaL_checkinteger(L, 3);
	i32 marker = (i32)luaL_optinteger(L, 4, 0);
	lua_pushinteger(L, jnl_pslg_edge_add(g, p, q, marker));
	return 1;
}

// pslg:hole_add(x, y) -> index
static int l_pslg_hole_add(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	f64 x = luaL_checknumber(L, 2);
	f64 y = luaL_checknumber(L, 3);
	lua_pushinteger(L, jnl_pslg_hole_add(g, x, y));
	return 1;
}

// pslg:region_add(x, y, marker, max_area) -> index
static int l_pslg_region_add(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	f64 x = luaL_checknumber(L, 2);
	f64 y = luaL_checknumber(L, 3);
	i32 marker = (i32)luaL_optinteger(L, 4, 0);
	f64 max_area = luaL_optnumber(L, 5, -1.0);
	lua_pushinteger(L, jnl_pslg_region_add(g, x, y, marker, max_area));
	return 1;
}

// pslg:bbox() -> min_x, min_y, max_x, max_y
static int l_pslg_bbox(lua_State *L)
{
	struct jnl_pslg *g = check_pslg(L, 1);
	struct jnl_aabb bb = jnl_pslg_bbox(g);
	lua_pushnumber(L, bb.min_x);
	lua_pushnumber(L, bb.min_y);
	lua_pushnumber(L, bb.max_x);
	lua_pushnumber(L, bb.max_y);
	return 4;
}

// pslg.node_count, pslg.edge_count as __index properties
// simplest: just put them as methods
static int l_pslg_node_count(lua_State *L)
{
	lua_pushinteger(L, check_pslg(L, 1)->nodes.len);
	return 1;
}
static int l_pslg_edge_count(lua_State *L)
{
	lua_pushinteger(L, check_pslg(L, 1)->edges.len);
	return 1;
}

static const luaL_Reg pslg_methods[] = {
    {"node_add", l_pslg_node_add},
    {"node_get", l_pslg_node_get},
    {"node_find_nearest", l_pslg_node_find_nearest},
    {"node_find_or_add", l_pslg_node_find_or_add},
    {"edge_add", l_pslg_edge_add},
    {"hole_add", l_pslg_hole_add},
    {"region_add", l_pslg_region_add},
    {"bbox", l_pslg_bbox},
    {"node_count", l_pslg_node_count},
    {"edge_count", l_pslg_edge_count},
    {"__tostring", l_pslg_tostring},
    {"__gc", l_pslg_gc},
    {NULL, NULL}};

static const luaL_Reg geo2d_funcs[] = {{"pslg_new", l_pslg_new}, {NULL, NULL}};

int luaopen_geo2d_internal(lua_State *L)
{
	// Create the metatable and populate it
	luaL_newmetatable(L, PSLG_MT);
	luaL_setfuncs(L, pslg_methods, 0);
	// __index = itself, so pslg:node_add() works
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, geo2d_funcs);
	return 1;
}
