#ifndef JNL_EXPR_H
#define JNL_EXPR_H

#include "jnl/common.h"
#include "jnl/arena.h"
#include "scratch.h"

//
// Expr data types
//

typedef enum {
	EXPR_CONST, // scalar
	EXPR_ARRAY, // borrowed f64* leaf
	EXPR_ADD,
	EXPR_SUB,
	EXPR_MUL,
	EXPR_DIV,
	EXPR_NEG,
	EXPR_POW,
} jnl_expr_kind;

typedef struct jnl_expr jnl_expr;

struct jnl_expr {
	jnl_expr_kind kind;
	union {
		f64 value;        // EXPR_CONST
		const f64 *array; // EXPR_ARRAY (borrowed)
		struct {          // binary ops
			jnl_expr *a, *b;
		} bin;
		struct { // EXPR_NEG (unary ops)
			jnl_expr *operand;
		} un;
	};
};

//
// Node constructors (arena allocated)
//

jnl_expr *jnl_expr_const(jnl_arena *a, f64 value);
jnl_expr *jnl_expr_array(jnl_arena *a, const f64 *array);
jnl_expr *jnl_expr_add(jnl_arena *a, jnl_expr *l, jnl_expr *r);
jnl_expr *jnl_expr_sub(jnl_arena *a, jnl_expr *l, jnl_expr *r);
jnl_expr *jnl_expr_mul(jnl_arena *a, jnl_expr *l, jnl_expr *r);
jnl_expr *jnl_expr_div(jnl_arena *a, jnl_expr *l, jnl_expr *r);
jnl_expr *jnl_expr_neg(jnl_arena *a, jnl_expr *operand);
jnl_expr *jnl_expr_pow(jnl_arena *a, jnl_expr *base, jnl_expr *exp);

//
// Static analysis
//

i32 jnl_expr_scratch_depth(const jnl_expr *e);

//
// Evaluation
//

// Evaluate e across n elements using pool for scratch.
// Returns a pointer into the pool valid until jnl_scratch_reset(pool).
// Caller must NOT release it.
const f64 *jnl_expr_eval(const jnl_expr *e, i32 n,
                         struct jnl_scratch_pool *pool);

#endif // JNL_EXPR_H
