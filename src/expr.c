#include <math.h>
#include <string.h>
#include <assert.h>

#include "expr.h"
#include "jnl/arena.h"

//
// Constructors
//

static jnl_expr *alloc_node(jnl_arena *a)
{
	return ARENA_PUSH_STRUCT_Z(a, jnl_expr);
}

jnl_expr *jnl_expr_const(jnl_arena *a, f64 value)
{
	jnl_expr *e = alloc_node(a);
	e->kind = EXPR_CONST;
	e->value = value;
	return e;
}

jnl_expr *jnl_expr_array(jnl_arena *a, const f64 *array)
{
	jnl_expr *e = alloc_node(a);
	e->kind = EXPR_ARRAY;
	e->array = array;
	return e;
}

static jnl_expr *binop(jnl_arena *a, jnl_expr_kind k, jnl_expr *l, jnl_expr *r)
{
	jnl_expr *e = alloc_node(a);
	e->kind = k;
	e->bin.a = l;
	e->bin.b = r;
	return e;
}

jnl_expr *jnl_expr_add(jnl_arena *a, jnl_expr *l, jnl_expr *r)
{
	return binop(a, EXPR_ADD, l, r);
}

jnl_expr *jnl_expr_sub(jnl_arena *a, jnl_expr *l, jnl_expr *r)
{
	return binop(a, EXPR_SUB, l, r);
}

jnl_expr *jnl_expr_mul(jnl_arena *a, jnl_expr *l, jnl_expr *r)
{
	return binop(a, EXPR_MUL, l, r);
}

jnl_expr *jnl_expr_div(jnl_arena *a, jnl_expr *l, jnl_expr *r)
{
	return binop(a, EXPR_DIV, l, r);
}

jnl_expr *jnl_expr_pow(jnl_arena *a, jnl_expr *l, jnl_expr *r)
{
	return binop(a, EXPR_POW, l, r);
}

jnl_expr *jnl_expr_neg(jnl_arena *a, jnl_expr *operand)
{
	jnl_expr *e = alloc_node(a);
	e->kind = EXPR_NEG;
	e->un.operand = operand;
	return e;
}

//
// Evaluation
//

// Internal result: buf + whether the caller must release it
typedef struct {
	f64 *buf;
	bool owned;
} eval_r;

static void apply_binop(jnl_expr_kind op, const f64 *a, const f64 *b, f64 *out,
                        i32 n)
{
	switch (op) {
	case EXPR_ADD:
		for (i32 i = 0; i < n; i++)
			out[i] = a[i] + b[i];
		return;
	case EXPR_SUB:
		for (i32 i = 0; i < n; i++)
			out[i] = a[i] - b[i];
		return;
	case EXPR_MUL:
		for (i32 i = 0; i < n; i++)
			out[i] = a[i] * b[i];
		return;
	case EXPR_DIV:
		for (i32 i = 0; i < n; i++)
			out[i] = a[i] / b[i];
		return;
	case EXPR_POW:
		for (i32 i = 0; i < n; i++)
			out[i] = pow(a[i], b[i]);
		return;
	default:
		assert(0 && "apply_binop: not a binary op");
	}
}

static eval_r eval_node(const jnl_expr *e, i32 n, struct jnl_scratch_pool *pool)
{
	switch (e->kind) {

	case EXPR_CONST: {
		f64 *out = jnl_scratch_acquire(pool);
		for (i32 i = 0; i < n; i++)
			out[i] = e->value;
		return (eval_r){out, true};
	}

	case EXPR_ARRAY:
		return (eval_r){(f64 *)e->array, false};

	case EXPR_NEG: {
		eval_r r = eval_node(e->un.operand, n, pool);
		f64 *out = jnl_scratch_acquire(pool);
		for (i32 i = 0; i < n; i++)
			out[i] = -r.buf[i];
		if (r.owned)
			jnl_scratch_release(pool, r.buf);
		return (eval_r){out, true};
	}

	default: { // binary ops
		eval_r ra = eval_node(e->bin.a, n, pool);
		eval_r rb = eval_node(e->bin.b, n, pool);
		f64 *out = jnl_scratch_acquire(pool);
		apply_binop(e->kind, ra.buf, rb.buf, out, n);
		if (ra.owned)
			jnl_scratch_release(pool, ra.buf);
		if (rb.owned)
			jnl_scratch_release(pool, rb.buf);
		return (eval_r){out, true};
	}
	}
}

const f64 *jnl_expr_eval(const jnl_expr *e, i32 n,
                         struct jnl_scratch_pool *pool)
{
	eval_r r = eval_node(e, n, pool);
	// If the top-level result is an unowned ARRAY borrow, copy into
	// scratch so the caller always gets a stable pool-owned pointer.
	if (!r.owned) {
		f64 *out = jnl_scratch_acquire(pool);
		memcpy(out, r.buf, sizeof(f64) * (u64)n);
		return out;
	}
	return r.buf;
}
