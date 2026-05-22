#include <string.h>

#include "lua_bindings.h"
#include "jnl/arena.h"
#include "jnl/common.h"
#include "expr.h"

#define EXPR_MT "jnl.expr"
#define JNL_EXPR_ARENA_SIZE (16 * 1024)

//
// Userdata
//

typedef struct {
	jnl_expr *root;
	jnl_arena *arena;
	int *vec_refs;
	i32 n_vec_refs;
} lua_expr_ud;

static lua_expr_ud *check_expr(lua_State *L, int idx)
{
	return (lua_expr_ud *)luaL_checkudata(L, idx, EXPR_MT);
}

//
// Constructors
//

// expr_internal.new() -> expr_ud  (fresh arena, no root yet)
static int l_expr_new(lua_State *L)
{
	lua_expr_ud *ud = lua_newuserdata(L, sizeof(lua_expr_ud));
	ud->arena = arena_create(JNL_EXPR_ARENA_SIZE);
	ud->root = NULL;
	ud->vec_refs = NULL;
	ud->n_vec_refs = 0;
	luaL_setmetatable(L, EXPR_MT);
	return 1;
}

static int l_node_const(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	f64 v = luaL_checknumber(L, 2);
	lua_pushlightuserdata(L, jnl_expr_const(e->arena, v));
	return 1;
}

static int l_node_array(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	lua_vec *v = check_vec(L, 2);

	// Anchor the vec so it outlives the expr
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	// Grow refs array — arena-allocate a new one and copy
	int *new_refs = ARENA_PUSH_ARRAY(e->arena, int, e->n_vec_refs + 1);
	if (e->vec_refs)
		memcpy(new_refs, e->vec_refs, (u64)e->n_vec_refs * sizeof(int));
	new_refs[e->n_vec_refs] = ref;
	e->vec_refs = new_refs;
	e->n_vec_refs++;

	lua_pushlightuserdata(L, jnl_expr_array(e->arena, v->data));
	return 1;
}

static int l_node_binop(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	jnl_expr *a = (jnl_expr *)lua_touserdata(L, 2);
	jnl_expr *b = (jnl_expr *)lua_touserdata(L, 3);
	luaL_argcheck(L, a != NULL, 2, "expected expr node");
	luaL_argcheck(L, b != NULL, 3, "expected expr node");

	jnl_expr_kind kind =
	    (jnl_expr_kind)(int)lua_tointeger(L, lua_upvalueindex(1));

	jnl_expr *node;
	switch (kind) {
	case EXPR_ADD:
		node = jnl_expr_add(e->arena, a, b);
		break;
	case EXPR_SUB:
		node = jnl_expr_sub(e->arena, a, b);
		break;
	case EXPR_MUL:
		node = jnl_expr_mul(e->arena, a, b);
		break;
	case EXPR_DIV:
		node = jnl_expr_div(e->arena, a, b);
		break;
	case EXPR_POW:
		node = jnl_expr_pow(e->arena, a, b);
		break;
	default:
		return luaL_error(L, "unknown binop kind");
	}
	lua_pushlightuserdata(L, node);
	return 1;
}

static int l_node_neg(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	jnl_expr *operand = (jnl_expr *)lua_touserdata(L, 2);
	luaL_argcheck(L, operand != NULL, 2, "expected expr node");
	lua_pushlightuserdata(L, jnl_expr_neg(e->arena, operand));
	return 1;
}

// expr_ud:set_root(node_lightuserdata)
// Seals the tree — after this, eval is valid.
static int l_expr_set_root(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	jnl_expr *root = (jnl_expr *)lua_touserdata(L, 2);
	luaL_argcheck(L, root != NULL, 2, "expected expr node");
	e->root = root;
	return 0;
}

//
// Eval
//

// expr_ud:eval(pool, n_cells) -> scratch
static int l_expr_eval(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	struct jnl_scratch_pool *pool = check_pool(L, 2);
	i32 n = (i32)luaL_checkinteger(L, 3);
	luaL_argcheck(L, e->root != NULL, 1, "expr has no root");
	jnl_scratch_reset(pool);
	const f64 *result = jnl_expr_eval(e->root, n, pool);
	push_scratch_vec(L, (f64 *)result, n);
	return 1;
}

static int l_expr_tostring(lua_State *L)
{
	lua_expr_ud *e = check_expr(L, 1);
	if (e->root)
		lua_pushfstring(L, "expr(arrays=%d)", e->n_vec_refs);
	else
		lua_pushstring(L, "expr(unrooted)");
	return 1;
}

static int l_expr_gc(lua_State *L)
{
	lua_expr_ud *e = luaL_checkudata(L, 1, EXPR_MT);
	for (i32 i = 0; i < e->n_vec_refs; i++)
		luaL_unref(L, LUA_REGISTRYINDEX, e->vec_refs[i]);
	arena_destroy(e->arena);
	return 0;
}

//
// Module registration
//

static const luaL_Reg expr_mt[] = {{"set_root", l_expr_set_root},
                                   {"eval", l_expr_eval},
                                   {"__tostring", l_expr_tostring},
                                   {"__gc", l_expr_gc},
                                   {NULL, NULL}};

static void push_binop_fn(lua_State *L, jnl_expr_kind kind)
{
	lua_pushinteger(L, (int)kind);
	lua_pushcclosure(L, l_node_binop, 1);
}

int luaopen_expr_internal(lua_State *L)
{
	// Ensure VEC_MT is registered - idempotent
	luaL_requiref(L, "jnl.vec_internal", luaopen_vec_internal, 0);
	lua_pop(L, 1);

	// Ensure POOL_MT is registered - ditto
	luaL_requiref(L, "jnl.scratch_internal", luaopen_scratch_internal, 0);
	lua_pop(L, 1);

	// Register metatable
	luaL_newmetatable(L, EXPR_MT);
	luaL_setfuncs(L, expr_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	// Return module table
	lua_newtable(L);

	lua_pushcfunction(L, l_expr_new);
	lua_setfield(L, -2, "new");

	lua_pushcfunction(L, l_node_const);
	lua_setfield(L, -2, "const");

	lua_pushcfunction(L, l_node_array);
	lua_setfield(L, -2, "array");

	lua_pushcfunction(L, l_node_neg);
	lua_setfield(L, -2, "neg");

	push_binop_fn(L, EXPR_ADD);
	lua_setfield(L, -2, "add");
	push_binop_fn(L, EXPR_SUB);
	lua_setfield(L, -2, "sub");
	push_binop_fn(L, EXPR_MUL);
	lua_setfield(L, -2, "mul");
	push_binop_fn(L, EXPR_DIV);
	lua_setfield(L, -2, "div");
	push_binop_fn(L, EXPR_POW);
	lua_setfield(L, -2, "pow");

	// Do stuff
	return 1;
}
