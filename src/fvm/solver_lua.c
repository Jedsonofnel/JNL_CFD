#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/solver.h"

#define CG_JAC_SOLVE_MT "jnl.fvm.cg_jac_solve"
#define CG_DIC_SOLVE_MT "jnl.fvm.cg_dic_solve"
#define BICGSTAB_JAC_SOLVE_MT "jnl.fvm.bicgstab_jac_solve"
#define BICGSTAB_DILU_SOLVE_MT "jnl.fvm.bicgstab_dilu_solve"
#define GMRES_DILU_SOLVE_MT "jnl.fvm.gmres_dilu_solve"
#define JACOBI_SMOOTHER_MT "jnl.fvm.jacobi_smoother"

//
// Helpers
//

static void push_solver_step(lua_State *L, struct jnl_solver_step r)
{
	lua_createtable(L, 0, 5);

	lua_pushnumber(L, r.residual);
	lua_setfield(L, -2, "residual");

	lua_pushnumber(L, r.rel_residual);
	lua_setfield(L, -2, "rel_residual");

	lua_pushinteger(L, r.iter);
	lua_setfield(L, -2, "iter");

	lua_pushboolean(L, r.done);
	lua_setfield(L, -2, "done");

	lua_pushboolean(L, r.breakdown);
	lua_setfield(L, -2, "breakdown");
}

static void push_smoother_step(lua_State *L, struct jnl_smoother_step r)
{
	lua_createtable(L, 0, 3);

	lua_pushnumber(L, r.change);
	lua_setfield(L, -2, "change");

	lua_pushinteger(L, r.sweeps);
	lua_setfield(L, -2, "sweeps");

	lua_pushboolean(L, r.breakdown);
	lua_setfield(L, -2, "breakdown");
}

static void check_initial_vec_len(lua_State *L, const char *name, fvsys *s,
                                  lua_vec *x)
{
	if (x->len != s->matrix.n_cells) {
		luaL_error(L, "%s: initial vector length mismatch", name);
	}
}

static void check_finish_vec_len(lua_State *L, const char *name, i32 n_cells,
                                 lua_vec *x)
{
	if (x->len != n_cells) {
		luaL_error(L, "%s: finish vector length mismatch", name);
	}
}

//
// CG + Jacobi userdata
//

typedef struct {
	struct jnl_cg_jac solve;
	i32 n_cells;
	int fvsys_ref;
	int pool_ref;
} lua_cg_jac_solve;

static lua_cg_jac_solve *check_cg_jac_solve(lua_State *L, int idx)
{
	return (lua_cg_jac_solve *)luaL_checkudata(L, idx, CG_JAC_SOLVE_MT);
}

static int l_fvsys_cg_jac(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_checknumber(L, 3);
	lua_pool *pool = check_pool(L, 4);

	check_initial_vec_len(L, "cg_jac", s, x);

	lua_cg_jac_solve *ls = lua_newuserdata(L, sizeof(lua_cg_jac_solve));
	ls->n_cells = s->matrix.n_cells;
	ls->solve = jnl_fvsys_cg_jac_begin(s, pool, x->data, tol);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_pushvalue(L, 4);
	ls->pool_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, CG_JAC_SOLVE_MT);
	return 1;
}

static int l_cg_jac_iter(lua_State *L)
{
	lua_cg_jac_solve *s = check_cg_jac_solve(L, 1);
	push_solver_step(L, jnl_cg_jac_iter(&s->solve));
	return 1;
}

static int l_cg_jac_finish_into(lua_State *L)
{
	lua_cg_jac_solve *s = check_cg_jac_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "cg_jac", s->n_cells, x);

	jnl_cg_jac_finish_into(&s->solve, x->data);
	return 0;
}

static int l_cg_jac_finish_change_into(lua_State *L)
{
	lua_cg_jac_solve *s = check_cg_jac_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "cg_jac", s->n_cells, x);

	f64 change = jnl_cg_jac_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_cg_jac_tostring(lua_State *L)
{
	lua_cg_jac_solve *s = check_cg_jac_solve(L, 1);
	lua_pushfstring(L, "cg_jac_solve(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_cg_jac_gc(lua_State *L)
{
	lua_cg_jac_solve *s = check_cg_jac_solve(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	luaL_unref(L, LUA_REGISTRYINDEX, s->pool_ref);
	s->fvsys_ref = LUA_NOREF;
	s->pool_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg cg_jac_solve_mt[] = {
    {"iter", l_cg_jac_iter},
    {"finish_into", l_cg_jac_finish_into},
    {"finish_change_into", l_cg_jac_finish_change_into},
    {"__tostring", l_cg_jac_tostring},
    {"__gc", l_cg_jac_gc},
    {NULL, NULL}};

//
// CG + DIC userdata
//

typedef struct {
	struct jnl_cg_dic solve;
	i32 n_cells;
	int fvsys_ref;
	int pool_ref;
} lua_cg_dic_solve;

static lua_cg_dic_solve *check_cg_dic_solve(lua_State *L, int idx)
{
	return (lua_cg_dic_solve *)luaL_checkudata(L, idx, CG_DIC_SOLVE_MT);
}

static int l_fvsys_cg_dic(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_checknumber(L, 3);
	lua_pool *pool = check_pool(L, 4);

	check_initial_vec_len(L, "cg_dic", s, x);

	lua_cg_dic_solve *ls = lua_newuserdata(L, sizeof(lua_cg_dic_solve));
	ls->n_cells = s->matrix.n_cells;

	ls->solve = jnl_fvsys_cg_dic_begin(s, pool, x->data, tol);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_pushvalue(L, 4);
	ls->pool_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, CG_DIC_SOLVE_MT);
	return 1;
}

static int l_cg_dic_iter(lua_State *L)
{
	lua_cg_dic_solve *s = check_cg_dic_solve(L, 1);
	push_solver_step(L, jnl_cg_dic_iter(&s->solve));
	return 1;
}

static int l_cg_dic_finish_into(lua_State *L)
{
	lua_cg_dic_solve *s = check_cg_dic_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "cg_dic", s->n_cells, x);

	jnl_cg_dic_finish_into(&s->solve, x->data);
	return 0;
}

static int l_cg_dic_finish_change_into(lua_State *L)
{
	lua_cg_dic_solve *s = check_cg_dic_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "cg_dic", s->n_cells, x);

	f64 change = jnl_cg_dic_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_cg_dic_tostring(lua_State *L)
{
	lua_cg_dic_solve *s = check_cg_dic_solve(L, 1);
	lua_pushfstring(L, "cg_dic_solve(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_cg_dic_gc(lua_State *L)
{
	lua_cg_dic_solve *s = check_cg_dic_solve(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	luaL_unref(L, LUA_REGISTRYINDEX, s->pool_ref);
	s->fvsys_ref = LUA_NOREF;
	s->pool_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg cg_dic_solve_mt[] = {
    {"iter", l_cg_dic_iter},
    {"finish_into", l_cg_dic_finish_into},
    {"finish_change_into", l_cg_dic_finish_change_into},
    {"__tostring", l_cg_dic_tostring},
    {"__gc", l_cg_dic_gc},
    {NULL, NULL}};

//
// BiCGSTAB + Jacobi userdata
//

typedef struct {
	struct jnl_bicgstab_jac solve;
	i32 n_cells;
	int fvsys_ref;
	int pool_ref;
} lua_bicgstab_jac_solve;

static lua_bicgstab_jac_solve *check_bicgstab_jac_solve(lua_State *L, int idx)
{
	return (lua_bicgstab_jac_solve *)luaL_checkudata(L, idx,
	                                                 BICGSTAB_JAC_SOLVE_MT);
}

static int l_fvsys_bicgstab_jac(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_checknumber(L, 3);
	lua_pool *pool = check_pool(L, 4);

	check_initial_vec_len(L, "bicgstab_jac", s, x);

	lua_bicgstab_jac_solve *ls =
	    lua_newuserdata(L, sizeof(lua_bicgstab_jac_solve));

	ls->n_cells = s->matrix.n_cells;
	ls->solve = jnl_fvsys_bicgstab_jac_begin(s, pool, x->data, tol);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_pushvalue(L, 4);
	ls->pool_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, BICGSTAB_JAC_SOLVE_MT);
	return 1;
}

static int l_bicgstab_jac_iter(lua_State *L)
{
	lua_bicgstab_jac_solve *s = check_bicgstab_jac_solve(L, 1);
	push_solver_step(L, jnl_bicgstab_jac_iter(&s->solve));
	return 1;
}

static int l_bicgstab_jac_finish_into(lua_State *L)
{
	lua_bicgstab_jac_solve *s = check_bicgstab_jac_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "bicgstab_jac", s->n_cells, x);

	jnl_bicgstab_jac_finish_into(&s->solve, x->data);
	return 0;
}

static int l_bicgstab_jac_finish_change_into(lua_State *L)
{
	lua_bicgstab_jac_solve *s = check_bicgstab_jac_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "bicgstab_jac", s->n_cells, x);

	f64 change =
	    jnl_bicgstab_jac_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_bicgstab_jac_tostring(lua_State *L)
{
	lua_bicgstab_jac_solve *s = check_bicgstab_jac_solve(L, 1);
	lua_pushfstring(L, "bicgstab_jac_solve(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_bicgstab_jac_gc(lua_State *L)
{
	lua_bicgstab_jac_solve *s = check_bicgstab_jac_solve(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	luaL_unref(L, LUA_REGISTRYINDEX, s->pool_ref);
	s->fvsys_ref = LUA_NOREF;
	s->pool_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg bicgstab_jac_solve_mt[] = {
    {"iter", l_bicgstab_jac_iter},
    {"finish_into", l_bicgstab_jac_finish_into},
    {"finish_change_into", l_bicgstab_jac_finish_change_into},
    {"__tostring", l_bicgstab_jac_tostring},
    {"__gc", l_bicgstab_jac_gc},
    {NULL, NULL}};

//
// BiCGSTAB + DILU userdata
//

typedef struct {
	struct jnl_bicgstab_dilu solve;
	i32 n_cells;
	int fvsys_ref;
	int pool_ref;
} lua_bicgstab_dilu_solve;

static lua_bicgstab_dilu_solve *check_bicgstab_dilu_solve(lua_State *L, int idx)
{
	return (lua_bicgstab_dilu_solve *)luaL_checkudata(L, idx,
	                                                  BICGSTAB_DILU_SOLVE_MT);
}

static int l_fvsys_bicgstab_dilu(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_checknumber(L, 3);
	lua_pool *pool = check_pool(L, 4);

	check_initial_vec_len(L, "bicgstab_dilu", s, x);

	lua_bicgstab_dilu_solve *ls =
	    lua_newuserdata(L, sizeof(lua_bicgstab_dilu_solve));

	ls->n_cells = s->matrix.n_cells;
	ls->solve = jnl_fvsys_bicgstab_dilu_begin(s, pool, x->data, tol);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_pushvalue(L, 4);
	ls->pool_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, BICGSTAB_DILU_SOLVE_MT);
	return 1;
}

static int l_bicgstab_dilu_iter(lua_State *L)
{
	lua_bicgstab_dilu_solve *s = check_bicgstab_dilu_solve(L, 1);
	push_solver_step(L, jnl_bicgstab_dilu_iter(&s->solve));
	return 1;
}

static int l_bicgstab_dilu_finish_into(lua_State *L)
{
	lua_bicgstab_dilu_solve *s = check_bicgstab_dilu_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "bicgstab_dilu", s->n_cells, x);

	jnl_bicgstab_dilu_finish_into(&s->solve, x->data);
	return 0;
}

static int l_bicgstab_dilu_finish_change_into(lua_State *L)
{
	lua_bicgstab_dilu_solve *s = check_bicgstab_dilu_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "bicgstab_dilu", s->n_cells, x);

	f64 change =
	    jnl_bicgstab_dilu_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_bicgstab_dilu_tostring(lua_State *L)
{
	lua_bicgstab_dilu_solve *s = check_bicgstab_dilu_solve(L, 1);
	lua_pushfstring(L, "bicgstab_dilu_solve(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_bicgstab_dilu_gc(lua_State *L)
{
	lua_bicgstab_dilu_solve *s = check_bicgstab_dilu_solve(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	luaL_unref(L, LUA_REGISTRYINDEX, s->pool_ref);
	s->fvsys_ref = LUA_NOREF;
	s->pool_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg bicgstab_dilu_solve_mt[] = {
    {"iter", l_bicgstab_dilu_iter},
    {"finish_into", l_bicgstab_dilu_finish_into},
    {"finish_change_into", l_bicgstab_dilu_finish_change_into},
    {"__tostring", l_bicgstab_dilu_tostring},
    {"__gc", l_bicgstab_dilu_gc},
    {NULL, NULL}};

//
// GMRES + DILU userdata
//

typedef struct {
	struct jnl_gmres_dilu solve;
	i32 n_cells;
	int fvsys_ref;
	int pool_ref;
} lua_gmres_dilu_solve;

static lua_gmres_dilu_solve *check_gmres_dilu_solve(lua_State *L, int idx)
{
	return (lua_gmres_dilu_solve *)luaL_checkudata(L, idx, GMRES_DILU_SOLVE_MT);
}

static int l_fvsys_gmres_dilu(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_checknumber(L, 3);
	i32 restart = (i32)luaL_checkinteger(L, 4);
	lua_pool *pool = check_pool(L, 5);

	check_initial_vec_len(L, "gmres_dilu", s, x);

	lua_gmres_dilu_solve *ls = lua_newuserdata(L, sizeof(lua_gmres_dilu_solve));

	ls->n_cells = s->matrix.n_cells;
	ls->solve = jnl_fvsys_gmres_dilu_begin(s, pool, x->data, tol, restart);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_pushvalue(L, 5);
	ls->pool_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, GMRES_DILU_SOLVE_MT);
	return 1;
}

static int l_gmres_dilu_iter(lua_State *L)
{
	lua_gmres_dilu_solve *s = check_gmres_dilu_solve(L, 1);
	push_solver_step(L, jnl_gmres_dilu_iter(&s->solve));
	return 1;
}

static int l_gmres_dilu_finish_into(lua_State *L)
{
	lua_gmres_dilu_solve *s = check_gmres_dilu_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "gmres_dilu", s->n_cells, x);

	jnl_gmres_dilu_finish_into(&s->solve, x->data);
	return 0;
}

static int l_gmres_dilu_finish_change_into(lua_State *L)
{
	lua_gmres_dilu_solve *s = check_gmres_dilu_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "gmres_dilu", s->n_cells, x);

	f64 change = jnl_gmres_dilu_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_gmres_dilu_destroy(lua_State *L)
{
	lua_gmres_dilu_solve *s = check_gmres_dilu_solve(L, 1);
	jnl_gmres_dilu_destroy(&s->solve);
	return 0;
}

static int l_gmres_dilu_tostring(lua_State *L)
{
	lua_gmres_dilu_solve *s = check_gmres_dilu_solve(L, 1);
	lua_pushfstring(L, "gmres_dilu_solve(n_cells=%d, restart=%d)", s->n_cells,
	                s->solve.restart);
	return 1;
}

static int l_gmres_dilu_gc(lua_State *L)
{
	lua_gmres_dilu_solve *s = check_gmres_dilu_solve(L, 1);

	jnl_gmres_dilu_destroy(&s->solve);

	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	luaL_unref(L, LUA_REGISTRYINDEX, s->pool_ref);
	s->fvsys_ref = LUA_NOREF;
	s->pool_ref = LUA_NOREF;

	return 0;
}

static const luaL_Reg gmres_dilu_solve_mt[] = {
    {"iter", l_gmres_dilu_iter},
    {"finish_into", l_gmres_dilu_finish_into},
    {"finish_change_into", l_gmres_dilu_finish_change_into},
    {"destroy", l_gmres_dilu_destroy},
    {"__tostring", l_gmres_dilu_tostring},
    {"__gc", l_gmres_dilu_gc},
    {NULL, NULL}};

//
// Jacobi smoother userdata
//

typedef struct {
	struct jnl_jacobi_smoother smooth;
	i32 n_cells;
	int fvsys_ref;
	int pool_ref;
} lua_jacobi_smoother;

static lua_jacobi_smoother *check_jacobi_smoother(lua_State *L, int idx)
{
	return (lua_jacobi_smoother *)luaL_checkudata(L, idx, JACOBI_SMOOTHER_MT);
}

static int l_fvsys_jacobi_smoother(lua_State *L)
{
	fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 omega = luaL_checknumber(L, 3);
	lua_pool *pool = check_pool(L, 4);

	check_initial_vec_len(L, "jacobi_smoother", s, x);

	lua_jacobi_smoother *ls = lua_newuserdata(L, sizeof(lua_jacobi_smoother));

	ls->n_cells = s->matrix.n_cells;
	ls->smooth =
	    jnl_fvsys_jacobi_smoother_begin(s, pool, x->data, omega);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_pushvalue(L, 4);
	ls->pool_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, JACOBI_SMOOTHER_MT);
	return 1;
}

static int l_jacobi_smoother_sweep(lua_State *L)
{
	lua_jacobi_smoother *s = check_jacobi_smoother(L, 1);
	push_smoother_step(L, jnl_jacobi_smoother_sweep(&s->smooth));
	return 1;
}

static int l_jacobi_smoother_finish_into(lua_State *L)
{
	lua_jacobi_smoother *s = check_jacobi_smoother(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "jacobi_smoother", s->n_cells, x);

	jnl_jacobi_smoother_finish_into(&s->smooth, x->data);
	return 0;
}

static int l_jacobi_smoother_finish_change_into(lua_State *L)
{
	lua_jacobi_smoother *s = check_jacobi_smoother(L, 1);
	lua_vec *x = check_vec(L, 2);

	check_finish_vec_len(L, "jacobi_smoother", s->n_cells, x);

	f64 change =
	    jnl_jacobi_smoother_finish_change_into(&s->smooth, x->data, x->data);

	lua_pushnumber(L, change);
	return 1;
}

static int l_jacobi_smoother_tostring(lua_State *L)
{
	lua_jacobi_smoother *s = check_jacobi_smoother(L, 1);
	lua_pushfstring(L, "jacobi_smoother(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_jacobi_smoother_gc(lua_State *L)
{
	lua_jacobi_smoother *s = check_jacobi_smoother(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	luaL_unref(L, LUA_REGISTRYINDEX, s->pool_ref);
	s->fvsys_ref = LUA_NOREF;
	s->pool_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg jacobi_smoother_mt[] = {
    {"sweep", l_jacobi_smoother_sweep},
    {"finish_into", l_jacobi_smoother_finish_into},
    {"finish_change_into", l_jacobi_smoother_finish_change_into},
    {"__tostring", l_jacobi_smoother_tostring},
    {"__gc", l_jacobi_smoother_gc},
    {NULL, NULL}};

//
// Registration
//

static void register_mt(lua_State *L, const char *name, const luaL_Reg *mt)
{
	luaL_newmetatable(L, name);
	luaL_setfuncs(L, mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

void jnl_lua_register_fvm_solver(lua_State *L)
{
	register_mt(L, CG_JAC_SOLVE_MT, cg_jac_solve_mt);
	register_mt(L, CG_DIC_SOLVE_MT, cg_dic_solve_mt);

	register_mt(L, BICGSTAB_JAC_SOLVE_MT, bicgstab_jac_solve_mt);
	register_mt(L, BICGSTAB_DILU_SOLVE_MT, bicgstab_dilu_solve_mt);

	register_mt(L, GMRES_DILU_SOLVE_MT, gmres_dilu_solve_mt);

	register_mt(L, JACOBI_SMOOTHER_MT, jacobi_smoother_mt);

	// Attach solver constructors to fvsys metatable.
	luaL_getmetatable(L, FVSYS_MT);

	lua_pushcfunction(L, l_fvsys_cg_jac);
	lua_setfield(L, -2, "cg_jac");

	lua_pushcfunction(L, l_fvsys_cg_dic);
	lua_setfield(L, -2, "cg_dic");

	lua_pushcfunction(L, l_fvsys_bicgstab_jac);
	lua_setfield(L, -2, "bicgstab_jac");

	lua_pushcfunction(L, l_fvsys_bicgstab_dilu);
	lua_setfield(L, -2, "bicgstab_dilu");

	lua_pushcfunction(L, l_fvsys_gmres_dilu);
	lua_setfield(L, -2, "gmres_dilu");

	lua_pushcfunction(L, l_fvsys_jacobi_smoother);
	lua_setfield(L, -2, "jacobi_smoother");

	lua_pop(L, 1);
}
