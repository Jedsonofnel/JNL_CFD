#include <math.h>
#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/field.h"

static int l_face_interp_cds(lua_State *L)
{
	jnl_face_interp_cds(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                    check_vec(L, 3)->data);
	return 0;
}

static int l_face_normal_component(lua_State *L)
{
	jnl_face_normal_component(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                          check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_face_normal_component_cds(lua_State *L)
{
	jnl_face_normal_component_cds(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                              check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_rhie_chow(lua_State *L)
{
	jnl_rhie_chow(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data,
	    check_vec(L, 4)->data, check_vec(L, 5)->data, check_vec(L, 6)->data,
	    check_vec(L, 7)->data, check_vec(L, 8)->data, check_vec(L, 9)->data);
	return 0;
}

static int l_grad_fill_ghosts_from_values(lua_State *L)
{
	jnl_grad_fill_ghosts_from_values(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                                 check_vec(L, 3)->data,
	                                 check_vec(L, 4)->data);
	return 0;
}

static int l_grad_green_gauss(lua_State *L)
{
	jnl_grad_green_gauss(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                     check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_grad_lsq(lua_State *L)
{
	jnl_grad_lsq(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	             check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_divergence2d_integrated_from_un(lua_State *L)
{
	jnl_divergence2d_integrated_from_un(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data);
	return 0;
}

static int l_divergence2d_volumetric_from_un(lua_State *L)
{
	jnl_divergence2d_volumetric_from_un(
	    check_pmsh2d(L, 1), check_vec(L, 2)->data, check_vec(L, 3)->data);
	return 0;
}

static int l_divergence2d_integrated(lua_State *L)
{
	jnl_divergence2d_integrated(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                            check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_divergence2d_volumetric(lua_State *L)
{
	jnl_divergence2d_volumetric(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                            check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_vorticity2d(lua_State *L)
{
	jnl_vorticity2d(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_patch_gradient_flux(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	lua_vec *phi = check_vec(L, 2);
	lua_vec *gx = check_vec(L, 3);
	lua_vec *gy = check_vec(L, 4);
	f64 gamma = luaL_checknumber(L, 5);
	const char *patch = luaL_checkstring(L, 6);

	f64 flux =
	    jnl_patch_gradient_flux(m, phi->data, gx->data, gy->data, gamma, patch);

	if (isnan(flux))
		return luaL_error(L, "patch_gradient_flux: unknown patch '%s'", patch);

	lua_pushnumber(L, flux);
	return 1;
}

static int l_field_fill_ghosts_copy_owner(lua_State *L)
{
	jnl_field_fill_ghosts_copy_owner(check_pmsh2d(L, 1), check_vec(L, 2)->data);
	return 0;
}

static int l_field_fill_ghosts_const(lua_State *L)
{
	jnl_field_fill_ghosts_const(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                            luaL_checknumber(L, 3));
	return 0;
}

static int l_field_from_fvsys_diag(lua_State *L)
{
	jnl_field_from_fvsys_diag(check_pmsh2d(L, 1), check_fvsys(L, 2)->sys,
	                          check_vec(L, 3)->data);
	return 0;
}

static const luaL_Reg field_funcs[] = {
    {"face_interp_cds", l_face_interp_cds},
    {"face_normal_component", l_face_normal_component},
    {"face_normal_component_cds", l_face_normal_component_cds},
    {"rhie_chow", l_rhie_chow},

    {"grad_fill_ghosts_from_values", l_grad_fill_ghosts_from_values},
    {"grad_green_gauss", l_grad_green_gauss},
    {"grad_lsq", l_grad_lsq},

    {"divergence2d_integrated_from_un", l_divergence2d_integrated_from_un},
    {"divergence2d_volumetric_from_un", l_divergence2d_volumetric_from_un},
    {"divergence2d_integrated", l_divergence2d_integrated},
    {"divergence2d_volumetric", l_divergence2d_volumetric},

    // Short aliases
    {"divergence_integrated", l_divergence2d_integrated_from_un},
    {"divergence_volumetric", l_divergence2d_volumetric_from_un},

    {"vorticity2d", l_vorticity2d},
    {"patch_gradient_flux", l_patch_gradient_flux},

    {"field_fill_ghosts_copy_owner", l_field_fill_ghosts_copy_owner},
    {"field_fill_ghosts_const", l_field_fill_ghosts_const},
    {"field_from_fvsys_diag", l_field_from_fvsys_diag},

    {NULL, NULL}};

void jnl_lua_register_fvm_field(lua_State *L)
{
	luaL_setfuncs(L, field_funcs, 0);
}
