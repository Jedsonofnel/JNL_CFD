#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "fields.h"

struct jnl_ui_field *field_map_find(struct jnl_ui_field_map *fm,
                                    const char *name)
{
	for (i32 i = 0; i < fm->n_fields; i++)
		if (strncmp(fm->fields[i].name, name, JNL_UI_FIELD_NAME_CAP) == 0)
			return &fm->fields[i];
	return NULL;
}

struct jnl_ui_vector *field_map_find_vector(struct jnl_ui_field_map *fm,
                                            const char *name)
{
	for (i32 i = 0; i < fm->n_vectors; i++)
		if (strncmp(fm->vectors[i].name, name, JNL_UI_FIELD_NAME_CAP) == 0)
			return &fm->vectors[i];
	return NULL;
}

static void field_compute_range(struct jnl_ui_field *f)
{
	if (f->n == 0) {
		f->vmin = 0.0;
		f->vmax = 1.0;
		return;
	}
	f->vmin = f->vmax = f->data[0];
	for (u32 i = 1; i < f->n; i++) {
		if (f->data[i] < f->vmin)
			f->vmin = f->data[i];
		if (f->data[i] > f->vmax)
			f->vmax = f->data[i];
	}
	if (f->vmin == f->vmax)
		f->vmax = f->vmin + 1.0;
}

struct jnl_ui_field *field_map_upsert(struct jnl_ui_field_map *fm,
                                      const char *name, const f64 *data,
                                      unsigned n)
{
	struct jnl_ui_field *f = field_map_find(fm, name);
	if (!f) {
		if (fm->n_fields == fm->cap_fields) {
			i32 cap = fm->cap_fields ? fm->cap_fields * 2 : 8;
			struct jnl_ui_field *p =
			    realloc(fm->fields, (size_t)cap * sizeof *p);
			if (!p)
				return NULL;
			fm->fields = p;
			fm->cap_fields = cap;
		}
		f = &fm->fields[fm->n_fields++];
		memset(f, 0, sizeof *f);
		strncpy(f->name, name, JNL_UI_FIELD_NAME_CAP - 1);
	}

	if (f->n != n) {
		free(f->data);
		f->data = malloc((size_t)n * sizeof(f64));
		if (!f->data) {
			f->n = 0;
			return NULL;
		}
		f->n = n;
	}

	memcpy(f->data, data, (size_t)n * sizeof(f64));
	f->tex_dirty = true;
	field_compute_range(f);
	return f;
}

int field_map_upsert_vector(struct jnl_ui_field_map *fm, const char *name,
                            const char *fx, const char *fy)
{
	struct jnl_ui_vector *v = field_map_find_vector(fm, name);

	if (!v) {
		if (fm->n_vectors == fm->cap_vectors) {
			i32 cap = fm->cap_vectors ? fm->cap_vectors * 2 : 8;
			struct jnl_ui_vector *p =
			    realloc(fm->vectors, (size_t)cap * sizeof *p);

			if (!p)
				return -1;

			fm->vectors = p;
			fm->cap_vectors = cap;
		}

		v = &fm->vectors[fm->n_vectors++];
		memset(v, 0, sizeof *v);
	}

	strncpy(v->name, name, JNL_UI_FIELD_NAME_CAP - 1);
	strncpy(v->fx, fx, JNL_UI_FIELD_NAME_CAP - 1);
	strncpy(v->fy, fy, JNL_UI_FIELD_NAME_CAP - 1);
	return 0;
}

unsigned field_map_vector_magnitude(const struct jnl_ui_field_map *fm,
                                    const char *vector_name, f64 *out,
                                    unsigned cap)
{
	const struct jnl_ui_vector *v = NULL;

	for (i32 i = 0; i < fm->n_vectors; i++)
		if (strncmp(fm->vectors[i].name, vector_name, JNL_UI_FIELD_NAME_CAP) ==
		    0) {
			v = &fm->vectors[i];
			break;
		}

	if (!v)
		return 0;

	const struct jnl_ui_field *fx =
	    field_map_find((struct jnl_ui_field_map *)fm, v->fx);
	const struct jnl_ui_field *fy =
	    field_map_find((struct jnl_ui_field_map *)fm, v->fy);
	if (!fx || !fy || fx->n != fy->n || fx->n > cap)
		return 0;

	for (unsigned i = 0; i < fx->n; i++) {
		f64 vx = fx->data[i], vy = fy->data[i];
		out[i] = sqrt(vx * vx + vy * vy);
	}
	return fx->n;
}

void field_map_free(struct jnl_ui_field_map *fm)
{
	for (i32 i = 0; i < fm->n_fields; i++)
		free(fm->fields[i].data);

	free(fm->fields);
	free(fm->vectors);
	memset(fm, 0, sizeof *fm);
}
