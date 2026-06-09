#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/operators.h"

//
// DDT
//

static int l_ddt_k(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	f64 dt = luaL_checknumber(L, 4);
	lua_vec *phi_old = check_vec(L, 5);

	jnl_ddt_k(s->sys, m, rho, dt, phi_old->data);
	return 0;
}

static int l_ddt_f(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *rho = check_vec(L, 3);
	f64 dt = luaL_checknumber(L, 4);
	lua_vec *phi_old = check_vec(L, 5);

	jnl_ddt_f(s->sys, m, rho->data, dt, phi_old->data);
	return 0;
}

//
// Laplacian
//

static int l_laplacian_k(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 gamma = luaL_checknumber(L, 3);

	jnl_laplacian_k(s->sys, m, gamma);
	return 0;
}

static int l_laplacian_f(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *gamma = check_vec(L, 3);

	jnl_laplacian_f(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_nonorth_k(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 gamma = luaL_checknumber(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);

	jnl_laplacian_nonorth_k(s->sys, m, gamma, gx->data, gy->data);
	return 0;
}

static int l_laplacian_nonorth_f(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *gamma = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);

	jnl_laplacian_nonorth_f(s->sys, m, gamma->data, gx->data, gy->data);
	return 0;
}

//
// Div CDS / UDS
//

static int l_div_cds_k(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_cds_k(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_cds_f(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *rho = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_cds_f(s->sys, m, rho->data, un->data);
	return 0;
}

static int l_div_uds_k(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_uds_k(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_uds_f(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *rho = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_uds_f(s->sys, m, rho->data, un->data);
	return 0;
}

//
// TVD corrections
//

static int l_div_tvd_minmod(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *phi = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	lua_vec *un = check_vec(L, 6);

	jnl_div_tvd_correction_minmod(s->sys, m, phi->data, gx->data, gy->data,
	                              un->data);
	return 0;
}

static int l_div_tvd_van_leer(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *phi = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	lua_vec *un = check_vec(L, 6);

	jnl_div_tvd_correction_van_leer(s->sys, m, phi->data, gx->data, gy->data,
	                                un->data);
	return 0;
}

static int l_div_tvd_superbee(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *phi = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	lua_vec *un = check_vec(L, 6);

	jnl_div_tvd_correction_superbee(s->sys, m, phi->data, gx->data, gy->data,
	                                un->data);
	return 0;
}

//
// Su
//

static int l_su_v_k(lua_State *L)
{
	jnl_su_v_k(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           luaL_checknumber(L, 3));
	return 0;
}

static int l_su_v_f(lua_State *L)
{
	jnl_su_v_f(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           check_vec(L, 3)->data);
	return 0;
}

static int l_su_v_fs(lua_State *L)
{
	f64 scale = luaL_checknumber(L, 3);
	jnl_su_v_fs(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), scale,
	            check_vec(L, 3)->data);
	return 0;
}

static int l_su_i_k(lua_State *L)
{
	jnl_su_i_k(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           luaL_checknumber(L, 3));
	return 0;
}

static int l_su_i_f(lua_State *L)
{
	jnl_su_i_f(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           check_vec(L, 3)->data);
	return 0;
}

static int l_su_i_fs(lua_State *L)
{
	f64 scale = luaL_checknumber(L, 3);
	jnl_su_i_fs(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), scale,
	            check_vec(L, 3)->data);
	return 0;
}

//
// Sp
//

static int l_sp_v_k(lua_State *L)
{
	jnl_sp_v_k(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           luaL_checknumber(L, 3));
	return 0;
}

static int l_sp_v_f(lua_State *L)
{
	jnl_sp_v_f(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           check_vec(L, 3)->data);
	return 0;
}

static int l_sp_v_fs(lua_State *L)
{
	f64 scale = luaL_checknumber(L, 3);
	jnl_sp_v_fs(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), scale,
	            check_vec(L, 3)->data);
	return 0;
}

static int l_sp_i_k(lua_State *L)
{
	jnl_sp_i_k(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           luaL_checknumber(L, 3));
	return 0;
}

static int l_sp_i_f(lua_State *L)
{
	jnl_sp_i_f(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	           check_vec(L, 3)->data);
	return 0;
}

static int l_sp_i_fs(lua_State *L)
{
	f64 scale = luaL_checknumber(L, 3);
	jnl_sp_i_fs(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2), scale,
	            check_vec(L, 3)->data);
	return 0;
}

static const luaL_Reg operator_funcs[] = {
    // unsteady term
    {"ddt_k", l_ddt_k},
    {"ddt_f", l_ddt_f},

    // laplacian/diffusive term
    {"laplacian_k", l_laplacian_k},
    {"laplacian_f", l_laplacian_f},
    {"laplacian_nonorth_k", l_laplacian_nonorth_k},
    {"laplacian_nonorth_f", l_laplacian_nonorth_f},

    // divergence/convection term
    {"div_cds_k", l_div_cds_k},
    {"div_cds_f", l_div_cds_f},
    {"div_uds_k", l_div_uds_k},
    {"div_uds_f", l_div_uds_f},

    // deferred correction for div
    {"div_tvd_minmod", l_div_tvd_minmod},
    {"div_tvd_van_leer", l_div_tvd_van_leer},
    {"div_tvd_superbee", l_div_tvd_superbee},

    // constant term
    {"su_v_k", l_su_v_k},
    {"su_v_f", l_su_v_f},
    {"su_v_fs", l_su_v_fs},
    {"su_i_k", l_su_i_k},
    {"su_i_f", l_su_i_f},
    {"su_i_fs", l_su_i_fs},

    // linear term
    {"sp_v_k", l_sp_v_k},
    {"sp_v_f", l_sp_v_f},
    {"sp_v_fs", l_sp_v_fs},
    {"sp_i_k", l_sp_i_k},
    {"sp_i_f", l_sp_i_f},
    {"sp_i_fs", l_sp_i_fs},

    {NULL, NULL}};

void jnl_lua_register_fvm_operators(lua_State *L)
{
	luaL_setfuncs(L, operator_funcs, 0);
}
