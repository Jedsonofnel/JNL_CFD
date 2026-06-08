#include <lauxlib.h>
#include <lua.h>

#include "lua_bindings.h"
#include "fvm/solver.h"

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

//
// CG solve userdata
//

typedef struct {
	struct jnl_cg solve;
	i32 n_cells;
	int fvsys_ref;
} lua_cg_solve;

static lua_cg_solve *check_cg_solve(lua_State *L, int idx)
{
	return (lua_cg_solve *)luaL_checkudata(L, idx, CG_SOLVE_MT);
}

static int l_fvsys_cg(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);

	if (x->len != s->sys->matrix.n_cells)
		return luaL_error(L, "cg: initial vector length mismatch");

	lua_cg_solve *ls = lua_newuserdata(L, sizeof(lua_cg_solve));
	ls->n_cells = s->sys->matrix.n_cells;

	ls->solve = jnl_fvsys_cg_begin(s->sys, s->pool, x->data, tol);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, CG_SOLVE_MT);
	return 1;
}

static int l_cg_iter(lua_State *L)
{
	lua_cg_solve *s = check_cg_solve(L, 1);
	push_solver_step(L, jnl_cg_iter(&s->solve));
	return 1;
}

static int l_cg_finish_into(lua_State *L)
{
	lua_cg_solve *s = check_cg_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	if (x->len != s->n_cells)
		return luaL_error(L, "cg: finish_into vector length mismatch");

	jnl_cg_finish_into(&s->solve, x->data);
	return 0;
}

static int l_cg_finish_change_into(lua_State *L)
{
	lua_cg_solve *s = check_cg_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	if (x->len != s->n_cells)
		return luaL_error(L, "cg: finish_change_into vector length mismatch");

	f64 change = jnl_cg_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_cg_tostring(lua_State *L)
{
	lua_cg_solve *s = check_cg_solve(L, 1);
	lua_pushfstring(L, "cg_solve(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_cg_gc(lua_State *L)
{
	lua_cg_solve *s = check_cg_solve(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	s->fvsys_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg cg_solve_mt[] = {
    {"iter", l_cg_iter},
    {"finish_into", l_cg_finish_into},
    {"finish_change_into", l_cg_finish_change_into},
    {"__tostring", l_cg_tostring},
    {"__gc", l_cg_gc},
    {NULL, NULL}};

//
// BiCGSTAB solve userdata
//

typedef struct {
	struct jnl_bicgstab solve;
	i32 n_cells;
	int fvsys_ref;
} lua_bicgstab_solve;

static lua_bicgstab_solve *check_bicgstab_solve(lua_State *L, int idx)
{
	return (lua_bicgstab_solve *)luaL_checkudata(L, idx, BICGSTAB_SOLVE_MT);
}

static int l_fvsys_bicgstab(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);

	if (x->len != s->sys->matrix.n_cells)
		return luaL_error(L, "bicgstab: initial vector length mismatch");

	lua_bicgstab_solve *ls = lua_newuserdata(L, sizeof(lua_bicgstab_solve));

	ls->n_cells = s->sys->matrix.n_cells;

	ls->solve = jnl_fvsys_bicgstab_begin(s->sys, s->pool, x->data, tol);

	lua_pushvalue(L, 1);
	ls->fvsys_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	luaL_setmetatable(L, BICGSTAB_SOLVE_MT);
	return 1;
}

static int l_bicgstab_iter(lua_State *L)
{
	lua_bicgstab_solve *s = check_bicgstab_solve(L, 1);
	push_solver_step(L, jnl_bicgstab_iter(&s->solve));
	return 1;
}

static int l_bicgstab_finish_into(lua_State *L)
{
	lua_bicgstab_solve *s = check_bicgstab_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	if (x->len != s->n_cells)
		return luaL_error(L, "bicgstab: finish_into vector length mismatch");

	jnl_bicgstab_finish_into(&s->solve, x->data);
	return 0;
}

static int l_bicgstab_finish_change_into(lua_State *L)
{
	lua_bicgstab_solve *s = check_bicgstab_solve(L, 1);
	lua_vec *x = check_vec(L, 2);

	if (x->len != s->n_cells)
		return luaL_error(
		    L, "bicgstab: finish_change_into vector length mismatch");

	f64 change = jnl_bicgstab_finish_change_into(&s->solve, x->data, x->data);
	lua_pushnumber(L, change);
	return 1;
}

static int l_bicgstab_tostring(lua_State *L)
{
	lua_bicgstab_solve *s = check_bicgstab_solve(L, 1);
	lua_pushfstring(L, "bicgstab_solve(n_cells=%d)", s->n_cells);
	return 1;
}

static int l_bicgstab_gc(lua_State *L)
{
	lua_bicgstab_solve *s = check_bicgstab_solve(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, s->fvsys_ref);
	s->fvsys_ref = LUA_NOREF;
	return 0;
}

static const luaL_Reg bicgstab_solve_mt[] = {
    {"iter", l_bicgstab_iter},
    {"finish_into", l_bicgstab_finish_into},
    {"finish_change_into", l_bicgstab_finish_change_into},
    {"__tostring", l_bicgstab_tostring},
    {"__gc", l_bicgstab_gc},
    {NULL, NULL}};

//
// Registration
//

void jnl_lua_register_fvm_solver(lua_State *L)
{
	// Register CG solve metatable
	luaL_newmetatable(L, CG_SOLVE_MT);
	luaL_setfuncs(L, cg_solve_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	// Register BiCGSTAB solve metatable
	luaL_newmetatable(L, BICGSTAB_SOLVE_MT);
	luaL_setfuncs(L, bicgstab_solve_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	// Attach solver constructors to fvsys metatable.
	luaL_getmetatable(L, FVSYS_MT);

	lua_pushcfunction(L, l_fvsys_cg);
	lua_setfield(L, -2, "cg");

	lua_pushcfunction(L, l_fvsys_bicgstab);
	lua_setfield(L, -2, "bicgstab");

	lua_pop(L, 1);
}
