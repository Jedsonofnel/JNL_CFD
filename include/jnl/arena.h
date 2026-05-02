#ifndef JNL_ARENA_H
#define JNL_ARENA_H

#include <stdbool.h>

#include "jnl/common.h"

#define ALIGN_UP_POW2(n, p) (((u64)(n) + ((u64)(p) - 1)) & (~((u64)(p) - 1)))
#define JNL_ARENA_BASE_POS (sizeof(jnl_arena))
#define JNL_ARENA_ALIGN (sizeof(void *))

struct jnl_arena {
	u64 cap, pos;
};

typedef struct jnl_arena jnl_arena;

jnl_arena *arena_create(u64 cap);
void arena_destroy(jnl_arena *arena);
void *arena_push(jnl_arena *arena, u64 size, bool zero);
void arena_pop(jnl_arena *arena, u64 size);
void arena_pop_to(jnl_arena *arena, u64 pos);
void arena_clear(jnl_arena *arena);

#define ARENA_PUSH_STRUCT(arena, T) (T *)arena_push((arena), sizeof(T), false)
#define ARENA_PUSH_STRUCT_Z(arena, T) (T *)arena_push((arena), sizeof(T), true)

#define ARENA_PUSH_ARRAY(arena, T, n)                                          \
	(T *)arena_push((arena), sizeof(T) * (n), false)
#define ARENA_PUSH_ARRAY_Z(arena, T, n)                                        \
	(T *)arena_push((arena), sizeof(T) * (n), true)

#define ARENA_ALLOC_SIZE(T, n) (sizeof(T) * (n) + JNL_ARENA_ALIGN)

#endif
