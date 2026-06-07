#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/bc.h"

//
// Scalar patch fill
//

static int l_patch_scalar_fill_dirichlet(lua_State *L)
{
	jnl_patch_scalar_fill_dirichlet(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                                luaL_checkstring(L, 3),
	                                luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_scalar_fill_neumann(lua_State *L)
{
	jnl_patch_scalar_fill_neumann(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                              luaL_checkstring(L, 3),
	                              luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_scalar_fill_robin(lua_State *L)
{
	jnl_patch_scalar_fill_robin(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                            luaL_checkstring(L, 3), luaL_checknumber(L, 4),
	                            luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

//
// Scalar patch close
//

static int l_patch_scalar_close_dirichlet(lua_State *L)
{
	jnl_patch_scalar_close_dirichlet(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                                 luaL_checkstring(L, 3),
	                                 luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_scalar_close_neumann(lua_State *L)
{
	jnl_patch_scalar_close_neumann(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                               luaL_checkstring(L, 3),
	                               luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_scalar_close_robin(lua_State *L)
{
	jnl_patch_scalar_close_robin(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3),
	    luaL_checknumber(L, 4), luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

//
// Scalar baffle-region fill
//

static int l_baffle_region_scalar_fill_dirichlet(lua_State *L)
{
	jnl_baffle_region_scalar_fill_dirichlet(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, luaL_checkstring(L, 3),
	    (i32)luaL_checkinteger(L, 4), luaL_checknumber(L, 5));
	return 0;
}

static int l_baffle_region_scalar_fill_neumann(lua_State *L)
{
	jnl_baffle_region_scalar_fill_neumann(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, luaL_checkstring(L, 3),
	    (i32)luaL_checkinteger(L, 4), luaL_checknumber(L, 5));
	return 0;
}

static int l_baffle_region_scalar_fill_robin(lua_State *L)
{
	jnl_baffle_region_scalar_fill_robin(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, luaL_checkstring(L, 3),
	    (i32)luaL_checkinteger(L, 4), luaL_checknumber(L, 5),
	    luaL_checknumber(L, 6), luaL_checknumber(L, 7));
	return 0;
}

//
// Scalar baffle-region close
//

static int l_baffle_region_scalar_close_dirichlet(lua_State *L)
{
	jnl_baffle_region_scalar_close_dirichlet(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3),
	    (i32)luaL_checkinteger(L, 4), luaL_checknumber(L, 5));
	return 0;
}

static int l_baffle_region_scalar_close_neumann(lua_State *L)
{
	jnl_baffle_region_scalar_close_neumann(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3),
	    (i32)luaL_checkinteger(L, 4), luaL_checknumber(L, 5));
	return 0;
}

static int l_baffle_region_scalar_close_robin(lua_State *L)
{
	jnl_baffle_region_scalar_close_robin(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3),
	    (i32)luaL_checkinteger(L, 4), luaL_checknumber(L, 5),
	    luaL_checknumber(L, 6), luaL_checknumber(L, 7));
	return 0;
}

//
// Whole scalar baffles
//

static int l_baffle_scalar_fill_insulated(lua_State *L)
{
	jnl_baffle_scalar_fill_insulated(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                                 luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_scalar_close_insulated(lua_State *L)
{
	jnl_baffle_scalar_close_insulated(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3));
	return 0;
}

static int l_baffles_scalar_fill_insulated(lua_State *L)
{
	jnl_baffles_scalar_fill_insulated(check_pmsh2d(L, 1),
	                                  check_vec(L, 2)->data);
	return 0;
}

static int l_baffles_scalar_close_insulated(lua_State *L)
{
	jnl_baffles_scalar_close_insulated(check_fvsys(L, 1)->sys,
	                                   check_pmsh2d(L, 2));
	return 0;
}

static int l_baffle_scalar_fill_continuous(lua_State *L)
{
	jnl_baffle_scalar_fill_continuous(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                                  luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_scalar_close_continuous(lua_State *L)
{
	jnl_baffle_scalar_close_continuous(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_scalar_close_contact_conductance(lua_State *L)
{
	jnl_baffle_scalar_close_contact_conductance(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3),
	    luaL_checknumber(L, 4));
	return 0;
}

static int l_baffle_scalar_close_contact_resistance(lua_State *L)
{
	jnl_baffle_scalar_close_contact_resistance(
	    check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), luaL_checkstring(L, 3),
	    luaL_checknumber(L, 4));
	return 0;
}

//
// Vector2 patch fill
//

static int l_patch_vector2_fill_dirichlet(lua_State *L)
{
	jnl_patch_vector2_fill_dirichlet(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

static int l_patch_vector2_fill_neumann(lua_State *L)
{
	jnl_patch_vector2_fill_neumann(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

static int l_patch_vector2_fill_zero_gradient(lua_State *L)
{
	jnl_patch_vector2_fill_zero_gradient(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4));
	return 0;
}

static int l_patch_vector2_fill_no_slip(lua_State *L)
{
	jnl_patch_vector2_fill_no_slip(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                               check_vec(L, 3)->data,
	                               luaL_checkstring(L, 4));
	return 0;
}

static int l_patch_vector2_fill_moving_wall(lua_State *L)
{
	jnl_patch_vector2_fill_moving_wall(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

static int l_patch_vector2_fill_nt(lua_State *L)
{
	jnl_patch_vector2_fill_nt(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), (jnl_bc_kind)luaL_checkinteger(L, 5),
	    luaL_checknumber(L, 6), (jnl_bc_kind)luaL_checkinteger(L, 7),
	    luaL_checknumber(L, 8));
	return 0;
}

static int l_patch_vector2_fill_slip(lua_State *L)
{
	jnl_patch_vector2_fill_slip(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                            check_vec(L, 3)->data, luaL_checkstring(L, 4));
	return 0;
}

static int l_patch_vector2_fill_symmetry(lua_State *L)
{
	jnl_patch_vector2_fill_symmetry(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                                check_vec(L, 3)->data,
	                                luaL_checkstring(L, 4));
	return 0;
}

//
// Vector2 baffle fill
//

static int l_baffle_region_vector2_fill_slip(lua_State *L)
{
	jnl_baffle_region_vector2_fill_slip(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), (i32)luaL_checkinteger(L, 5));
	return 0;
}

static int l_baffle_region_vector2_fill_symmetry(lua_State *L)
{
	jnl_baffle_region_vector2_fill_symmetry(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), (i32)luaL_checkinteger(L, 5));
	return 0;
}

static int l_baffle_vector2_fill_continuous(lua_State *L)
{
	jnl_baffle_vector2_fill_continuous(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4));
	return 0;
}

static int l_bc_assert_all_closed(lua_State *L)
{
	jnl_bc_assert_all_closed(check_fvsys(L, 1)->sys);
	return 0;
}

static const luaL_Reg bc_funcs[] = {
    {"patch_scalar_fill_dirichlet", l_patch_scalar_fill_dirichlet},
    {"patch_scalar_fill_neumann", l_patch_scalar_fill_neumann},
    {"patch_scalar_fill_robin", l_patch_scalar_fill_robin},

    {"patch_scalar_close_dirichlet", l_patch_scalar_close_dirichlet},
    {"patch_scalar_close_neumann", l_patch_scalar_close_neumann},
    {"patch_scalar_close_robin", l_patch_scalar_close_robin},

    {"baffle_region_scalar_fill_dirichlet",
     l_baffle_region_scalar_fill_dirichlet},
    {"baffle_region_scalar_fill_neumann", l_baffle_region_scalar_fill_neumann},
    {"baffle_region_scalar_fill_robin", l_baffle_region_scalar_fill_robin},

    {"baffle_region_scalar_close_dirichlet",
     l_baffle_region_scalar_close_dirichlet},
    {"baffle_region_scalar_close_neumann",
     l_baffle_region_scalar_close_neumann},
    {"baffle_region_scalar_close_robin", l_baffle_region_scalar_close_robin},

    {"baffle_scalar_fill_insulated", l_baffle_scalar_fill_insulated},
    {"baffle_scalar_close_insulated", l_baffle_scalar_close_insulated},
    {"baffles_scalar_fill_insulated", l_baffles_scalar_fill_insulated},
    {"baffles_scalar_close_insulated", l_baffles_scalar_close_insulated},

    {"baffle_scalar_fill_continuous", l_baffle_scalar_fill_continuous},
    {"baffle_scalar_close_continuous", l_baffle_scalar_close_continuous},
    {"baffle_scalar_close_contact_conductance",
     l_baffle_scalar_close_contact_conductance},
    {"baffle_scalar_close_contact_resistance",
     l_baffle_scalar_close_contact_resistance},

    {"patch_vector2_fill_dirichlet", l_patch_vector2_fill_dirichlet},
    {"patch_vector2_fill_neumann", l_patch_vector2_fill_neumann},
    {"patch_vector2_fill_zero_gradient", l_patch_vector2_fill_zero_gradient},
    {"patch_vector2_fill_no_slip", l_patch_vector2_fill_no_slip},
    {"patch_vector2_fill_moving_wall", l_patch_vector2_fill_moving_wall},
    {"patch_vector2_fill_nt", l_patch_vector2_fill_nt},
    {"patch_vector2_fill_slip", l_patch_vector2_fill_slip},
    {"patch_vector2_fill_symmetry", l_patch_vector2_fill_symmetry},

    {"baffle_region_vector2_fill_slip", l_baffle_region_vector2_fill_slip},
    {"baffle_region_vector2_fill_symmetry",
     l_baffle_region_vector2_fill_symmetry},
    {"baffle_vector2_fill_continuous", l_baffle_vector2_fill_continuous},

    {"bc_assert_all_closed", l_bc_assert_all_closed},

    // Legacy-ish aliases
    {"bc_dirichlet_const", l_patch_scalar_close_dirichlet},
    {"bc_neumann_const", l_patch_scalar_close_neumann},
    {"bc_robin_const", l_patch_scalar_close_robin},

    {NULL, NULL}};

void jnl_lua_register_fvm_bc(lua_State *L)
{
	luaL_setfuncs(L, bc_funcs, 0);

	lua_pushinteger(L, JNL_BC_NEUMANN);
	lua_setfield(L, -2, "BC_NEUMANN");

	lua_pushinteger(L, JNL_BC_DIRICHLET);
	lua_setfield(L, -2, "BC_DIRICHLET");

	lua_pushinteger(L, JNL_BC_ROBIN);
	lua_setfield(L, -2, "BC_ROBIN");
}
