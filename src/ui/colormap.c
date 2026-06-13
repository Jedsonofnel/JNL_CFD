#include <string.h>
#include "colormap.h"

void jnl_ui_colormap_eval(const struct jnl_ui_colormap *cm, float t, float *r,
                          float *g, float *b)
{
	if (cm->n_stops == 0) {
		*r = *g = *b = 0.0f;
		return;
	}

	if (t <= cm->stops[0].t) {
		*r = cm->stops[0].r;
		*g = cm->stops[0].g;
		*b = cm->stops[0].b;
		return;
	}

	if (t >= cm->stops[cm->n_stops - 1].t) {
		const struct jnl_ui_colormap_stop *s = &cm->stops[cm->n_stops - 1];
		*r = s->r;
		*g = s->g;
		*b = s->b;
		return;
	}

	for (int i = 0; i < cm->n_stops - 1; i++) {
		const struct jnl_ui_colormap_stop *lo = &cm->stops[i];
		const struct jnl_ui_colormap_stop *hi = &cm->stops[i + 1];

		if (t >= lo->t && t <= hi->t) {
			float u = (t - lo->t) / (hi->t - lo->t);
			*r = lo->r + u * (hi->r - lo->r);
			*g = lo->g + u * (hi->g - lo->g);
			*b = lo->b + u * (hi->b - lo->b);
			return;
		}
	}
}

void jnl_ui_colormap_bake(const struct jnl_ui_colormap *cm, int n,
                          unsigned char *out)
{
	for (int i = 0; i < n; i++) {
		float t = (n > 1) ? (float)i / (float)(n - 1) : 0.0f;
		float r, g, b;
		jnl_ui_colormap_eval(cm, t, &r, &g, &b);

		out[i * 4 + 0] = (unsigned char)(r * 255.0f + 0.5f);
		out[i * 4 + 1] = (unsigned char)(g * 255.0f + 0.5f);
		out[i * 4 + 2] = (unsigned char)(b * 255.0f + 0.5f);
		out[i * 4 + 3] = 255;
	}
}

//
// Presets
//

struct jnl_ui_colormap jnl_ui_colormap_cool_to_warm(void)
{
	struct jnl_ui_colormap cm;
	memset(&cm, 0, sizeof cm);
	strncpy(cm.name, "Cool to Warm", JNL_COLORMAP_NAME_CAP - 1);

	cm.n_stops = 5;
	cm.stops[0] = (struct jnl_ui_colormap_stop){0.000f, 0.231f, 0.298f, 0.753f};
	cm.stops[1] = (struct jnl_ui_colormap_stop){0.250f, 0.553f, 0.690f, 0.996f};
	cm.stops[2] = (struct jnl_ui_colormap_stop){0.500f, 0.867f, 0.867f, 0.867f};
	cm.stops[3] = (struct jnl_ui_colormap_stop){0.750f, 0.957f, 0.584f, 0.404f};
	cm.stops[4] = (struct jnl_ui_colormap_stop){1.000f, 0.706f, 0.016f, 0.149f};
	return cm;
}

struct jnl_ui_colormap jnl_ui_colormap_viridis(void)
{
	struct jnl_ui_colormap cm;
	memset(&cm, 0, sizeof cm);
	strncpy(cm.name, "Viridis", JNL_COLORMAP_NAME_CAP - 1);

	cm.n_stops = 5;
	cm.stops[0] = (struct jnl_ui_colormap_stop){0.000f, 0.267f, 0.005f, 0.329f};
	cm.stops[1] = (struct jnl_ui_colormap_stop){0.250f, 0.229f, 0.322f, 0.545f};
	cm.stops[2] = (struct jnl_ui_colormap_stop){0.500f, 0.128f, 0.566f, 0.551f};
	cm.stops[3] = (struct jnl_ui_colormap_stop){0.750f, 0.370f, 0.788f, 0.384f};
	cm.stops[4] = (struct jnl_ui_colormap_stop){1.000f, 0.993f, 0.906f, 0.144f};
	return cm;
}

struct jnl_ui_colormap jnl_ui_colormap_plasma(void)
{
	struct jnl_ui_colormap cm;
	memset(&cm, 0, sizeof cm);
	strncpy(cm.name, "Plasma", JNL_COLORMAP_NAME_CAP - 1);

	cm.n_stops = 5;
	cm.stops[0] = (struct jnl_ui_colormap_stop){0.000f, 0.050f, 0.030f, 0.528f};
	cm.stops[1] = (struct jnl_ui_colormap_stop){0.250f, 0.479f, 0.001f, 0.659f};
	cm.stops[2] = (struct jnl_ui_colormap_stop){0.500f, 0.799f, 0.175f, 0.408f};
	cm.stops[3] = (struct jnl_ui_colormap_stop){0.750f, 0.973f, 0.585f, 0.025f};
	cm.stops[4] = (struct jnl_ui_colormap_stop){1.000f, 0.940f, 0.975f, 0.131f};
	return cm;
}

struct jnl_ui_colormap jnl_ui_colormap_grayscale(void)
{
	struct jnl_ui_colormap cm;
	memset(&cm, 0, sizeof cm);
	strncpy(cm.name, "Grayscale", JNL_COLORMAP_NAME_CAP - 1);

	cm.n_stops = 2;
	cm.stops[0] = (struct jnl_ui_colormap_stop){0.0f, 0.0f, 0.0f, 0.0f};
	cm.stops[1] = (struct jnl_ui_colormap_stop){1.0f, 1.0f, 1.0f, 1.0f};
	return cm;
}
