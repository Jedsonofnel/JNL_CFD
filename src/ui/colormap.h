#ifndef JNL_UI_COLORMAP_H
#define JNL_UI_COLORMAP_H

#define JNL_COLORMAP_NAME_CAP 32
#define JNL_COLORMAP_MAX_STOPS 16

struct jnl_ui_colormap_stop {
	float t;       // position in [0, 1]
	float r, g, b; // RGB in [0, 1]
};

struct jnl_ui_colormap {
	char name[JNL_COLORMAP_NAME_CAP];
	int n_stops;
	struct jnl_ui_colormap_stop stops[JNL_COLORMAP_MAX_STOPS];
};

// Evaluate at t in [0,1], writing rgb in [0,1].
void jnl_ui_colormap_eval(const struct jnl_ui_colormap *cm, float t, float *r,
                          float *g, float *b);

// Bake n RGBA8 pixels into out (must be n*4 bytes).
void jnl_ui_colormap_bake(const struct jnl_ui_colormap *cm, int n,
                          unsigned char *out);

// Presets
struct jnl_ui_colormap jnl_ui_colormap_cool_to_warm(void); // Paraview default
struct jnl_ui_colormap jnl_ui_colormap_viridis(void);
struct jnl_ui_colormap jnl_ui_colormap_plasma(void);
struct jnl_ui_colormap jnl_ui_colormap_grayscale(void);

#endif // JNL_UI_COLORMAP_H
