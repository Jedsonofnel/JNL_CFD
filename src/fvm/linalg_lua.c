#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/ctx.h"
#include "fvm/linalg.h"

//
// FVSys userdata
//

static int l_fvsys_tostring(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_pushfstring(L, "fvsys(n_cells=%d, n_coupled_faces=%d)",
	                s->sys->matrix.n_cells, s->sys->matrix.n_coupled_faces);
	return 1;
}

static int l_fvsys_reset(lua_State *L)
{
	jnl_fvsys_reset(check_fvsys(L, 1)->sys);
	return 0;
}

static int l_fvsys_reset_singularity(lua_State *L)
{
	jnl_fvsys_reset_singularity(check_fvsys(L, 1)->sys);
	return 0;
}

static int l_fvsys_under_relax(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *v = check_vec(L, 2);
	f64 alpha = luaL_checknumber(L, 3);

	jnl_fvsys_under_relax(s->sys, v->data, alpha);
	return 0;
}

static int l_fvsys_pin_cell(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	i32 cell = (i32)luaL_checkinteger(L, 2) - 1;
	f64 val = luaL_checknumber(L, 3);

	jnl_fvsys_pin_cell(s->sys, cell, val);
	return 0;
}

static int l_fvsys_residual_norm(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);

	lua_pushnumber(L, jnl_fvsys_residual_norm(s->sys, s->pool, x->data));
	return 1;
}

static int l_fvsys_solve_cg(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	struct jnl_solve_result result =
	    jnl_fvsys_solve_cg(s->sys, s->pool, x->data, tol, max_iters);

	push_scratch_vec(L, result.x, s->sys->matrix.n_cells);
	lua_pushinteger(L, result.iters);
	return 2;
}

static int l_fvsys_solve_cg_into(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	i32 iters =
	    jnl_fvsys_solve_cg_into(s->sys, s->pool, x->data, tol, max_iters);

	lua_pushinteger(L, iters);
	return 1;
}

static int l_fvsys_solve_bicgstab(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	struct jnl_solve_result result =
	    jnl_fvsys_solve_bicgstab(s->sys, s->pool, x->data, tol, max_iters);

	push_scratch_vec(L, result.x, s->sys->matrix.n_cells);
	lua_pushinteger(L, result.iters);
	return 2;
}

static int l_fvsys_solve_bicgstab_into(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	i32 iters =
	    jnl_fvsys_solve_bicgstab_into(s->sys, s->pool, x->data, tol, max_iters);

	lua_pushinteger(L, iters);
	return 1;
}

static int l_fvsys_diag_vec(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	push_owned_vec(L, s->sys->matrix.diag, s->sys->matrix.n_cells, 1);
	return 1;
}

static int l_fvsys_diagonal_dominance(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_pushnumber(L, jnl_fvsys_diagonal_dominance(s->sys, s->pool));
	return 1;
}

static int l_fvsys_all_diagonals_positive(lua_State *L)
{
	lua_pushboolean(L,
	                jnl_fvsys_all_diagonals_positive(check_fvsys(L, 1)->sys));
	return 1;
}

static int l_fvsys_max_asymmetry(lua_State *L)
{
	lua_pushnumber(L, jnl_fvsys_max_asymmetry(check_fvsys(L, 1)->sys));
	return 1;
}

static int l_fvsys_gc(lua_State *L)
{
	luaL_unref(L, LUA_REGISTRYINDEX, check_fvsys(L, 1)->ctx_ref);
	return 0;
}

static const luaL_Reg fvsys_mt[] = {
    {"reset", l_fvsys_reset},
    {"reset_singularity", l_fvsys_reset_singularity},
    {"under_relax", l_fvsys_under_relax},
    {"pin_cell", l_fvsys_pin_cell},
    {"residual_norm", l_fvsys_residual_norm},
    {"solve_cg", l_fvsys_solve_cg},
    {"solve_bicgstab", l_fvsys_solve_bicgstab},
    {"solve_cg_into", l_fvsys_solve_cg_into},
    {"solve_bicgstab_into", l_fvsys_solve_bicgstab_into},
    {"diag_vec", l_fvsys_diag_vec},
    {"diagonal_dominance", l_fvsys_diagonal_dominance},
    {"all_diagonals_positive", l_fvsys_all_diagonals_positive},
    {"max_asymmetry", l_fvsys_max_asymmetry},
    {"__tostring", l_fvsys_tostring},
    {"__gc", l_fvsys_gc},
    {NULL, NULL}};

//
// Ctx userdata
//

static int l_ctx_field(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);
	push_owned_vec(L, jnl_fvm_ctx_alloc_field(lc->ctx), lc->ctx->n_cells, 1);
	return 1;
}

static int l_ctx_real_field(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);
	push_owned_vec(L, jnl_fvm_ctx_alloc_real_field(lc->ctx),
	               lc->ctx->n_real_cells, 1);
	return 1;
}

static int l_ctx_face_field(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);
	push_owned_vec(L, jnl_fvm_ctx_alloc_face_field(lc->ctx), lc->ctx->n_faces,
	               1);
	return 1;
}

static int l_ctx_fvsys(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);

	lua_fvsys *ls = lua_newuserdata(L, sizeof(lua_fvsys));
	ls->sys = jnl_fvm_ctx_alloc_fvsys(lc->ctx);
	ls->pool = lc->ctx->real_cell_pool;

	lua_pushvalue(L, 1);
	ls->ctx_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, FVSYS_MT);
	return 1;
}

static int l_ctx_cell_pool(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);
	push_borrowed_pool(L, lc->ctx->cell_pool, 1);
	return 1;
}

static int l_ctx_real_cell_pool(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);
	push_borrowed_pool(L, lc->ctx->real_cell_pool, 1);
	return 1;
}

static int l_ctx_face_pool(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_fvm_ctx(L, 1);
	push_borrowed_pool(L, lc->ctx->face_pool, 1);
	return 1;
}

static int l_ctx_n_cells(lua_State *L)
{
	lua_pushinteger(L, check_fvm_ctx(L, 1)->ctx->n_cells);
	return 1;
}

static int l_ctx_n_real_cells(lua_State *L)
{
	lua_pushinteger(L, check_fvm_ctx(L, 1)->ctx->n_real_cells);
	return 1;
}

static int l_ctx_n_faces(lua_State *L)
{
	lua_pushinteger(L, check_fvm_ctx(L, 1)->ctx->n_faces);
	return 1;
}

static int l_ctx_tostring(lua_State *L)
{
	struct jnl_fvm_ctx *c = check_fvm_ctx(L, 1)->ctx;
	lua_pushfstring(L, "fvm_ctx(n_cells=%d, n_real_cells=%d, n_faces=%d)",
	                c->n_cells, c->n_real_cells, c->n_faces);
	return 1;
}

static int l_ctx_gc(lua_State *L)
{
	jnl_fvm_ctx_free(check_fvm_ctx(L, 1)->ctx);
	return 0;
}

static const luaL_Reg ctx_mt[] = {{"field", l_ctx_field},
                                  {"real_field", l_ctx_real_field},
                                  {"face_field", l_ctx_face_field},
                                  {"cell_pool", l_ctx_cell_pool},
                                  {"real_cell_pool", l_ctx_real_cell_pool},
                                  {"face_pool", l_ctx_face_pool},
                                  {"n_cells", l_ctx_n_cells},
                                  {"n_real_cells", l_ctx_n_real_cells},
                                  {"n_faces", l_ctx_n_faces},
                                  {"fvsys", l_ctx_fvsys},
                                  {"__tostring", l_ctx_tostring},
                                  {"__gc", l_ctx_gc},
                                  {NULL, NULL}};

//
// Module-level ctx constructor
//

static int l_ctx_new(lua_State *L)
{
	pmsh2d *mesh = check_pmsh2d(L, 1);

	i32 n_fields = (i32)luaL_checkinteger(L, 2);
	i32 n_face_fields = (i32)luaL_checkinteger(L, 3);
	i32 n_systems = (i32)luaL_checkinteger(L, 4);

	i32 n_cell_scratch = (i32)luaL_optinteger(L, 5, 4);
	i32 n_real_cell_scratch = (i32)luaL_optinteger(L, 6, LINALG_MIN_SCRATCH);
	i32 n_face_scratch = (i32)luaL_optinteger(L, 7, 4);

	lua_fvm_ctx_ud *lc = lua_newuserdata(L, sizeof(lua_fvm_ctx_ud));

	lc->ctx =
	    jnl_fvm_ctx_new(mesh, n_fields, n_face_fields, n_systems,
	                    n_cell_scratch, n_real_cell_scratch, n_face_scratch);

	if (!lc->ctx)
		return luaL_error(L, "fvm_ctx allocation failed");

	luaL_setmetatable(L, CTX_MT);
	return 1;
}

static const luaL_Reg fvm_base_funcs[] = {
    {"ctx_new", l_ctx_new},
    {NULL, NULL},
};

int luaopen_fvm_internal(lua_State *L)
{
	luaL_requiref(L, "jnl.vec_internal", luaopen_vec_internal, 0);
	lua_pop(L, 1);

	luaL_requiref(L, "jnl.scratch_internal", luaopen_scratch_internal, 0);
	lua_pop(L, 1);

	luaL_newmetatable(L, FVSYS_MT);
	luaL_setfuncs(L, fvsys_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newmetatable(L, CTX_MT);
	luaL_setfuncs(L, ctx_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, fvm_base_funcs);

	jnl_lua_register_fvm_operators(L);
	jnl_lua_register_fvm_bc(L);
	jnl_lua_register_fvm_field(L);

	return 1;
}
