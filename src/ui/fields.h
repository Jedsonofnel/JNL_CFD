#ifndef JNL_UI_FIELDS_H
#define JNL_UI_FIELDS_H

#include "jnl/common.h"
#include "ui_internal.h"

// Linear scan — field counts are small (~10-20).
struct jnl_ui_field *field_map_find(struct jnl_ui_field_map *fm,
                                    const char *name);
struct jnl_ui_vector *field_map_find_vector(struct jnl_ui_field_map *fm,
                                            const char *name);

// Add or update a scalar field.  Returns the field on success, NULL on OOM.
struct jnl_ui_field *field_map_upsert(struct jnl_ui_field_map *fm,
                                      const char *name, const f64 *data,
                                      unsigned n);

// Associate two scalar fields as a named vector.  Returns 0 / -1.
int field_map_upsert_vector(struct jnl_ui_field_map *fm, const char *name,
                            const char *fx, const char *fy);

// Compute magnitude of a named vector into out[0..n-1].
// Returns n on success, 0 if either component field is missing or sizes differ.
unsigned field_map_vector_magnitude(const struct jnl_ui_field_map *fm,
                                    const char *vector_name, f64 *out,
                                    unsigned cap);

void field_map_free(struct jnl_ui_field_map *fm);

#endif // JNL_UI_FIELDS_H
