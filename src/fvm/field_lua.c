#include <math.h>
#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/field.h"

//
// Face interp
//

static int l_face_interp(lua_State *L)
{
	jnl_face_interp(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                check_vec(L, 3)->data);
	return 0;
}

static int l_face_normal(lua_State *L)
{
	jnl_face_normal(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_face_normal_c(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	lua_vec *ux = check_vec(L, 2);
	lua_vec *uy = check_vec(L, 3);
	lua_vec *out = check_vec(L, 4);
	lua_pool *pool = check_pool(L, 5);

	jnl_face_normal_c(m, ux->data, uy->data, out->data, pool);
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

//
// Gradient
//

static int l_grad_gg(lua_State *L)
{
	jnl_grad_gg(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	            check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

static int l_grad_lsq(lua_State *L)
{
	jnl_grad_lsq(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	             check_vec(L, 3)->data, check_vec(L, 4)->data);
	return 0;
}

//
// Divergence
//

static int l_divergence_i(lua_State *L)
{
	jnl_divergence_i(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                 check_vec(L, 3)->data);
	return 0;
}

static int l_divergence_i_c(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	lua_vec *ux = check_vec(L, 2);
	lua_vec *uy = check_vec(L, 3);
	lua_vec *out = check_vec(L, 4);
	lua_pool *pool = check_pool(L, 5);

	jnl_divergence_i_c(m, ux->data, uy->data, out->data, pool);
	return 0;
}

static int l_divergence_v(lua_State *L)
{
	jnl_divergence_v(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	                 check_vec(L, 3)->data);
	return 0;
}

static int l_divergence_v_c(lua_State *L)
{
	pmsh2d *m = check_pmsh2d(L, 1);
	lua_vec *ux = check_vec(L, 2);
	lua_vec *uy = check_vec(L, 3);
	lua_vec *out = check_vec(L, 4);
	lua_pool *pool = check_pool(L, 5);

	jnl_divergence_i_c(m, ux->data, uy->data, out->data, pool);
	return 0;
}

//
// Vorticity
//

static int l_vorticity(lua_State *L)
{
	jnl_vorticity(check_pmsh2d(L, 1), check_vec(L, 2)->data,
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

//
// Ghost helpers
//

static int l_ghost_copy(lua_State *L)
{
	jnl_ghost_copy(check_pmsh2d(L, 1), check_vec(L, 2)->data);
	return 0;
}

static int l_ghost_k(lua_State *L)
{
	jnl_ghost_k(check_pmsh2d(L, 1), check_vec(L, 2)->data,
	            luaL_checknumber(L, 3));
	return 0;
}

//
// System field metrics
//

static int l_diag_snapshot(lua_State *L)
{
	jnl_diag_snapshot(check_pmsh2d(L, 1), check_fvsys(L, 2),
	                  check_vec(L, 3)->data);
	return 0;
}

//
// Registration
//

static const luaL_Reg field_funcs[] = {
    {"face_interp", l_face_interp},
    {"face_normal", l_face_normal},
    {"face_normal_c", l_face_normal_c},
    {"rhie_chow", l_rhie_chow},

    {"grad_gg", l_grad_gg},
    {"grad_lsq", l_grad_lsq},

    {"divergence_i", l_divergence_i},
    {"divergence_i_c", l_divergence_i_c},
    {"divergence_v", l_divergence_v},
    {"divergence_v_c", l_divergence_v_c},

    {"vorticity", l_vorticity},
    {"patch_gradient_flux", l_patch_gradient_flux},

    {"ghost_copy", l_ghost_copy},
    {"ghost_k", l_ghost_k},
    {"diag_snapshot", l_diag_snapshot},

    {NULL, NULL}};

void jnl_lua_register_fvm_field(lua_State *L)
{
	luaL_setfuncs(L, field_funcs, 0);
}
