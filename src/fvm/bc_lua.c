#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/bc.h"

//
// Scalar patch fill
//

static int l_patch_s_fill_d(lua_State *L)
{
	jnl_patch_s_fill_d(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                   luaL_checkstring(L, 3), luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_s_fill_n(lua_State *L)
{
	jnl_patch_s_fill_n(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                   luaL_checkstring(L, 3), luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_s_fill_r(lua_State *L)
{
	jnl_patch_s_fill_r(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                   luaL_checkstring(L, 3), luaL_checknumber(L, 4),
	                   luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

//
// Scalar patch close
//

static int l_patch_s_close_d(lua_State *L)
{
	jnl_patch_s_close_d(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                    luaL_checkstring(L, 3), luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_s_close_n(lua_State *L)
{
	jnl_patch_s_close_n(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                    luaL_checkstring(L, 3), luaL_checknumber(L, 4));
	return 0;
}

static int l_patch_s_close_r(lua_State *L)
{
	jnl_patch_s_close_r(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                    luaL_checkstring(L, 3), luaL_checknumber(L, 4),
	                    luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

//
// Vector patch fill
//

static int l_patch_v_fill_d(lua_State *L)
{
	jnl_patch_v_fill_d(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                   check_vec(L, 3)->data, luaL_checkstring(L, 4),
	                   luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

static int l_patch_v_fill_n(lua_State *L)
{
	jnl_patch_v_fill_n(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                   check_vec(L, 3)->data, luaL_checkstring(L, 4),
	                   luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

static int l_patch_v_fill_nt(lua_State *L)
{
	jnl_patch_v_fill_nt(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), (jnl_bc_kind)luaL_checkinteger(L, 5),
	    luaL_checknumber(L, 6), (jnl_bc_kind)luaL_checkinteger(L, 7),
	    luaL_checknumber(L, 8));
	return 0;
}

//
// Scalar baffle-region fill
//

static int l_bregion_s_fill_d(lua_State *L)
{
	jnl_bregion_s_fill_d(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                     luaL_checkstring(L, 3), (i32)luaL_checkinteger(L, 4),
	                     luaL_checknumber(L, 5));
	return 0;
}

static int l_bregion_s_fill_n(lua_State *L)
{
	jnl_bregion_s_fill_n(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                     luaL_checkstring(L, 3), (i32)luaL_checkinteger(L, 4),
	                     luaL_checknumber(L, 5));
	return 0;
}

static int l_bregion_s_fill_r(lua_State *L)
{
	jnl_bregion_s_fill_r(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                     luaL_checkstring(L, 3), (i32)luaL_checkinteger(L, 4),
	                     luaL_checknumber(L, 5), luaL_checknumber(L, 6),
	                     luaL_checknumber(L, 7));
	return 0;
}

//
// Scalar baffle-region close
//

static int l_bregion_s_close_d(lua_State *L)
{
	jnl_bregion_s_close_d(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                      luaL_checkstring(L, 3), (i32)luaL_checkinteger(L, 4),
	                      luaL_checknumber(L, 5));
	return 0;
}

static int l_bregion_s_close_n(lua_State *L)
{
	jnl_bregion_s_close_n(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                      luaL_checkstring(L, 3), (i32)luaL_checkinteger(L, 4),
	                      luaL_checknumber(L, 5));
	return 0;
}

static int l_bregion_s_close_r(lua_State *L)
{
	jnl_bregion_s_close_r(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                      luaL_checkstring(L, 3), (i32)luaL_checkinteger(L, 4),
	                      luaL_checknumber(L, 5), luaL_checknumber(L, 6),
	                      luaL_checknumber(L, 7));
	return 0;
}

//
// Vector baffle-region BCs
//

static int l_bregion_v_fill_d(lua_State *L)
{
	jnl_bregion_v_fill_d(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                     check_vec(L, 3)->data, luaL_checkstring(L, 4),
	                     (i32)luaL_checkinteger(L, 5), luaL_checknumber(L, 6),
	                     luaL_checknumber(L, 7));
	return 0;
}

static int l_bregion_v_fill_n(lua_State *L)
{
	jnl_bregion_v_fill_n(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                     check_vec(L, 3)->data, luaL_checkstring(L, 4),
	                     (i32)luaL_checkinteger(L, 5), luaL_checknumber(L, 6),
	                     luaL_checknumber(L, 7));
	return 0;
}

static int l_bregion_v_fill_nt(lua_State *L)
{
	jnl_bregion_v_fill_nt(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    luaL_checkstring(L, 4), (i32)luaL_checkinteger(L, 5),
	    (jnl_bc_kind)luaL_checkinteger(L, 6), luaL_checknumber(L, 7),
	    (jnl_bc_kind)luaL_checkinteger(L, 8), luaL_checknumber(L, 9));
	return 0;
}

//
// Whole-baffle scalar helpers
//

static int l_baffle_s_fill_insul(lua_State *L)
{
	jnl_baffle_s_fill_insul(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                        luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_s_close_insul(lua_State *L)
{
	jnl_baffle_s_close_insul(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                         luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_s_fill_cont(lua_State *L)
{
	jnl_baffle_s_fill_cont(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                       luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_s_close_cont(lua_State *L)
{
	jnl_baffle_s_close_cont(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        luaL_checkstring(L, 3));
	return 0;
}

static int l_baffle_s_close_cc(lua_State *L)
{
	jnl_baffle_s_close_cc(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                      luaL_checkstring(L, 3), luaL_checknumber(L, 4));
	return 0;
}

static int l_baffle_s_close_cr(lua_State *L)
{
	jnl_baffle_s_close_cr(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                      luaL_checkstring(L, 3), luaL_checknumber(L, 4));
	return 0;
}

//
// All-baffles scalar helpers
//

static int l_baffles_s_fill_insul(lua_State *L)
{
	jnl_baffles_s_fill_insul(check_pmsh2d(L, 1), check_vec(L, 2)->data);
	return 0;
}

static int l_baffles_s_close_insul(lua_State *L)
{
	jnl_baffles_s_close_insul(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2));
	return 0;
}

//
// Whole-baffle vector helpers
//

static int l_baffle_v_fill_cont(lua_State *L)
{
	jnl_baffle_v_fill_cont(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                       check_vec(L, 3)->data, luaL_checkstring(L, 4));
	return 0;
}

//
// Debug
//

static int l_bc_assert_all_closed(lua_State *L)
{
	jnl_bc_assert_all_closed(check_fvsys(L, 1)->sys);
	return 0;
}

static const luaL_Reg bc_funcs[] = {
    // Scalar patch
    {"patch_s_fill_d", l_patch_s_fill_d},
    {"patch_s_fill_n", l_patch_s_fill_n},
    {"patch_s_fill_r", l_patch_s_fill_r},
    {"patch_s_close_d", l_patch_s_close_d},
    {"patch_s_close_n", l_patch_s_close_n},
    {"patch_s_close_r", l_patch_s_close_r},

    // Vector patch
    {"patch_v_fill_d", l_patch_v_fill_d},
    {"patch_v_fill_n", l_patch_v_fill_n},
    {"patch_v_fill_nt", l_patch_v_fill_nt},

    // Scalar baffle-region
    {"bregion_s_fill_d", l_bregion_s_fill_d},
    {"bregion_s_fill_n", l_bregion_s_fill_n},
    {"bregion_s_fill_r", l_bregion_s_fill_r},
    {"bregion_s_close_d", l_bregion_s_close_d},
    {"bregion_s_close_n", l_bregion_s_close_n},
    {"bregion_s_close_r", l_bregion_s_close_r},

    // Vector baffle-region
    {"bregion_v_fill_d", l_bregion_v_fill_d},
    {"bregion_v_fill_n", l_bregion_v_fill_n},
    {"bregion_v_fill_nt", l_bregion_v_fill_nt},

    // Whole-baffle scalar
    {"baffle_s_fill_insul", l_baffle_s_fill_insul},
    {"baffle_s_close_insul", l_baffle_s_close_insul},
    {"baffle_s_fill_cont", l_baffle_s_fill_cont},
    {"baffle_s_close_cont", l_baffle_s_close_cont},
    {"baffle_s_close_cc", l_baffle_s_close_cc},
    {"baffle_s_close_cr", l_baffle_s_close_cr},

    // All-baffles scalar
    {"baffles_s_fill_insul", l_baffles_s_fill_insul},
    {"baffles_s_close_insul", l_baffles_s_close_insul},

    // Whole-baffle vector
    {"baffle_v_fill_cont", l_baffle_v_fill_cont},

    {"bc_assert_all_closed", l_bc_assert_all_closed},

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
