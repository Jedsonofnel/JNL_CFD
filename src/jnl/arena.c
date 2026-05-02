#include <stdlib.h>
#include <string.h>

#include "jnl/arena.h"
#include "jnl/common.h"

struct jnl_arena *arena_create(u64 cap)
{
	u32 bumped_cap = cap + JNL_ARENA_BASE_POS;
	struct jnl_arena *arena = malloc(bumped_cap);
	arena->cap = bumped_cap;
	arena->pos = JNL_ARENA_BASE_POS;
	return arena;
}

void arena_destroy(struct jnl_arena *arena)
{
	if (!arena)
		return;

	free(arena);
}

void *arena_push(struct jnl_arena *arena, u64 size, bool zero)
{
	u64 pos_aligned = ALIGN_UP_POW2(arena->pos, JNL_ARENA_ALIGN);
	u64 new_pos = pos_aligned + size;

	if (new_pos > arena->cap) {
		return NULL; // TODO maybe exit out and throw an error?
	}

	u8 *out = (u8 *)arena + pos_aligned;

	if (zero) {
		memset(out, 0, size);
	}

	arena->pos = new_pos;
	return out;
}

void arena_pop(struct jnl_arena *arena, u64 size)
{
	size = MIN(size, arena->pos - JNL_ARENA_BASE_POS);
	arena->pos -= size;
}

void arena_pop_to(struct jnl_arena *arena, u64 pos)
{
	u64 size = pos < arena->pos ? arena->pos - pos : 0;
	arena_pop(arena, size);
}

void arena_clear(struct jnl_arena *arena)
{
	arena_pop_to(arena, JNL_ARENA_BASE_POS);
}
