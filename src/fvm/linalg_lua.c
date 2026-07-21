#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/linalg.h"

//
// FVSys userdata
//

static int l_fvsys_new(lua_State *L)
{
	pmsh2d *mesh = check_pmsh2d(L, 1);
	struct jnl_fvsys **pp = lua_newuserdata(L, sizeof(void *));
	*pp = jnl_fvsys_new(mesh);
	if (!*pp)
		return luaL_error(L, "fvsys allocation failed");
	luaL_setmetatable(L, FVSYS_MT);
	return 1;
}

static int l_fvsys_gc(lua_State *L)
{
	jnl_fvsys_free(check_fvsys(L, 1));
	return 0;
}

static int l_fvsys_tostring(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_pushfstring(L, "fvsys(n_cells=%d, n_coupled_faces=%d)",
	                s->matrix.n_cells, s->matrix.n_coupled_faces);
	return 1;
}

static int l_fvsys_reset(lua_State *L)
{
	jnl_fvsys_reset(check_fvsys(L, 1));
	return 0;
}

static int l_fvsys_reset_singularity(lua_State *L)
{
	jnl_fvsys_reset_singularity(check_fvsys(L, 1));
	return 0;
}

static int l_fvsys_under_relax(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *v = check_vec(L, 2);
	f64 alpha = luaL_checknumber(L, 3);

	jnl_fvsys_under_relax(s, v->data, alpha);
	return 0;
}

static int l_fvsys_pin_cell(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	i32 cell = (i32)luaL_checkinteger(L, 2) - 1;
	f64 val = luaL_checknumber(L, 3);

	jnl_fvsys_pin_cell(s, cell, val);
	return 0;
}

static int l_fvsys_residual_norm(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	lua_pool *pool = check_pool(L, 3);

	lua_pushnumber(L, jnl_fvsys_residual_norm(s, pool, x->data));
	return 1;
}

static int l_fvsys_diag_vec(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	push_view_vec(L, s->matrix.diag, s->matrix.n_cells, 1);
	return 1;
}

static int l_fvsys_diagonal_dominance(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_pool *pool = check_pool(L, 2);
	lua_pushnumber(L, jnl_fvsys_diagonal_dominance(s, pool));
	return 1;
}

static int l_fvsys_all_diagonals_positive(lua_State *L)
{
	lua_pushboolean(L, jnl_fvsys_all_diagonals_positive(check_fvsys(L, 1)));
	return 1;
}

static int l_fvsys_max_asymmetry(lua_State *L)
{
	lua_pushnumber(L, jnl_fvsys_max_asymmetry(check_fvsys(L, 1)));
	return 1;
}

static const luaL_Reg fvsys_mt[] = {
    {"reset", l_fvsys_reset},
    {"reset_singularity", l_fvsys_reset_singularity},
    {"under_relax", l_fvsys_under_relax},
    {"pin_cell", l_fvsys_pin_cell},
    {"residual_norm", l_fvsys_residual_norm},
    {"diag_vec", l_fvsys_diag_vec},
    {"diagonal_dominance", l_fvsys_diagonal_dominance},
    {"all_diagonals_positive", l_fvsys_all_diagonals_positive},
    {"max_asymmetry", l_fvsys_max_asymmetry},
    {"__tostring", l_fvsys_tostring},
    {"__gc", l_fvsys_gc},
    {NULL, NULL}};

//
// Registration
//

static const luaL_Reg fvm_base_funcs[] = {
    {"fvsys_new", l_fvsys_new},
    {NULL, NULL},
};

int luaopen_fvm_internal(lua_State *L)
{
	require_module(L, "jnl.vec_internal", luaopen_vec_internal);

	require_module(L, "jnl.scratch_internal", luaopen_scratch_internal);

	luaL_newmetatable(L, FVSYS_MT);
	luaL_setfuncs(L, fvsys_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, fvm_base_funcs);

	jnl_lua_register_fvm_operators(L);
	jnl_lua_register_fvm_bc(L);
	jnl_lua_register_fvm_field(L);
	jnl_lua_register_fvm_solver(L);

	return 1;
}
