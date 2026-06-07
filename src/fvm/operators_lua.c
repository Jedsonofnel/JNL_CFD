#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/operators.h"

//
// DDT
//

static int l_ddt_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	f64 dt = luaL_checknumber(L, 4);
	lua_vec *phi_old = check_vec(L, 5);

	jnl_ddt_const(s->sys, m, rho, dt, phi_old->data);
	return 0;
}

static int l_ddt_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *rho = check_vec(L, 3);
	f64 dt = luaL_checknumber(L, 4);
	lua_vec *phi_old = check_vec(L, 5);

	jnl_ddt_field(s->sys, m, rho->data, dt, phi_old->data);
	return 0;
}

//
// Laplacian
//

static int l_laplacian_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 gamma = luaL_checknumber(L, 3);

	jnl_laplacian_const(s->sys, m, gamma);
	return 0;
}

static int l_laplacian_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *gamma = check_vec(L, 3);

	jnl_laplacian_field(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_field_harmonic(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *gamma = check_vec(L, 3);

	jnl_laplacian_field_harmonic(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_nonorth_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 gamma = luaL_checknumber(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);

	jnl_laplacian_nonorth_const(s->sys, m, gamma, gx->data, gy->data);
	return 0;
}

static int l_laplacian_nonorth_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *gamma = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);

	jnl_laplacian_nonorth_field(s->sys, m, gamma->data, gx->data, gy->data);
	return 0;
}

//
// Div CDS / UDS
//

static int l_div_cds_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_cds_const(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_cds_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *rho = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_cds_field(s->sys, m, rho->data, un->data);
	return 0;
}

static int l_div_uds_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_uds_const(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_uds_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	pmsh2d *m = check_pmsh2d(L, 2);
	lua_vec *rho = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);

	jnl_div_uds_field(s->sys, m, rho->data, un->data);
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

static int l_su_volumetric_const(lua_State *L)
{
	jnl_su_volumetric_const(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        luaL_checknumber(L, 3));
	return 0;
}

static int l_su_volumetric_field(lua_State *L)
{
	jnl_su_volumetric_field(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        check_vec(L, 3)->data);
	return 0;
}

static int l_su_volumetric_field_scaled(lua_State *L)
{
	jnl_su_volumetric_field_scaled(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                               luaL_checknumber(L, 3),
	                               check_vec(L, 4)->data);
	return 0;
}

static int l_su_integrated_const(lua_State *L)
{
	jnl_su_integrated_const(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        luaL_checknumber(L, 3));
	return 0;
}

static int l_su_integrated(lua_State *L)
{
	jnl_su_integrated(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                  check_vec(L, 3)->data);
	return 0;
}

static int l_su_integrated_scaled(lua_State *L)
{
	jnl_su_integrated_scaled(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                         luaL_checknumber(L, 3), check_vec(L, 4)->data);
	return 0;
}

//
// Sp
//

static int l_sp_volumetric_const(lua_State *L)
{
	jnl_sp_volumetric_const(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        luaL_checknumber(L, 3));
	return 0;
}

static int l_sp_volumetric_field(lua_State *L)
{
	jnl_sp_volumetric_field(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        check_vec(L, 3)->data);
	return 0;
}

static int l_sp_volumetric_field_scaled(lua_State *L)
{
	jnl_sp_volumetric_field_scaled(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                               luaL_checknumber(L, 3),
	                               check_vec(L, 4)->data);
	return 0;
}

static int l_sp_integrated_const(lua_State *L)
{
	jnl_sp_integrated_const(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                        luaL_checknumber(L, 3));
	return 0;
}

static int l_sp_integrated(lua_State *L)
{
	jnl_sp_integrated(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                  check_vec(L, 3)->data);
	return 0;
}

static int l_sp_integrated_scaled(lua_State *L)
{
	jnl_sp_integrated_scaled(check_fvsys(L, 1)->sys, check_pmsh2d(L, 2),
	                         luaL_checknumber(L, 3), check_vec(L, 4)->data);
	return 0;
}

static const luaL_Reg operator_funcs[] = {
    {"ddt_const", l_ddt_const},
    {"ddt_field", l_ddt_field},

    {"laplacian_const", l_laplacian_const},
    {"laplacian_field", l_laplacian_field},
    {"laplacian_field_harmonic", l_laplacian_field_harmonic},
    {"laplacian_nonorth_const", l_laplacian_nonorth_const},
    {"laplacian_nonorth_field", l_laplacian_nonorth_field},

    {"div_cds_const", l_div_cds_const},
    {"div_cds_field", l_div_cds_field},
    {"div_uds_const", l_div_uds_const},
    {"div_uds_field", l_div_uds_field},

    {"div_tvd_minmod", l_div_tvd_minmod},
    {"div_tvd_van_leer", l_div_tvd_van_leer},
    {"div_tvd_superbee", l_div_tvd_superbee},

    {"su_volumetric_const", l_su_volumetric_const},
    {"su_volumetric_field", l_su_volumetric_field},
    {"su_volumetric_field_scaled", l_su_volumetric_field_scaled},
    {"su_integrated_const", l_su_integrated_const},
    {"su_integrated", l_su_integrated},
    {"su_integrated_scaled", l_su_integrated_scaled},

    {"sp_volumetric_const", l_sp_volumetric_const},
    {"sp_volumetric_field", l_sp_volumetric_field},
    {"sp_volumetric_field_scaled", l_sp_volumetric_field_scaled},
    {"sp_integrated_const", l_sp_integrated_const},
    {"sp_integrated", l_sp_integrated},
    {"sp_integrated_scaled", l_sp_integrated_scaled},

    {NULL, NULL}};

void jnl_lua_register_fvm_operators(lua_State *L)
{
	luaL_setfuncs(L, operator_funcs, 0);
}
