#ifndef JNL_PSLG2D_H
#define JNL_PSLG2D_H

#include <stdio.h>

#include "jnl/common.h"
#include "geo2d/vec2d.h"

#define PSLG_NOT_FOUND (-1)
#define PSLG_OOB (-2)
#define PSLG_OK (0)

//
// Nodes API
//

struct jnl_node_array {
	jnl_vec2d *coords;
	i32 *markers;
	u32 len, cap;
};

void jnl_node_array_init(struct jnl_node_array *ns);
void jnl_node_array_free(struct jnl_node_array *ns);

u32 jnl_node_array_add(struct jnl_node_array *ns, f64 x, f64 y, i32 marker);
u32 jnl_node_array_add_v(struct jnl_node_array *ns, jnl_vec2d v, i32 marker);
i32 jnl_node_array_find_nearest(const struct jnl_node_array *ns, f64 x, f64 y);
i32 jnl_node_array_find_nearest_v(const struct jnl_node_array *ns, jnl_vec2d v);
u32 jnl_node_array_find_or_add(struct jnl_node_array *ns, f64 x, f64 y,
                               i32 marker, f64 eps);
u32 jnl_node_array_find_or_add_v(struct jnl_node_array *ns, jnl_vec2d v,
                                 i32 marker, f64 eps);
i32 jnl_node_array_get(const struct jnl_node_array *ns, u32 index,
                       jnl_vec2d *out);

struct jnl_aabb jnl_node_array_bbox(const struct jnl_node_array *ns);

void jnl_node_array_write(const struct jnl_node_array *ns, FILE *file);

//
// Edges API
//

struct jnl_edge_array {
	u32 *ps, *qs;
	i32 *markers;
	u32 len, cap;
};

void jnl_edge_array_init(struct jnl_edge_array *es);
void jnl_edge_array_free(struct jnl_edge_array *es);

u32 jnl_edge_array_add(struct jnl_edge_array *es, u32 p, u32 q, i32 marker);

void jnl_edge_array_write(const struct jnl_edge_array *es, FILE *file);

//
// PSLG API
//

struct jnl_pslg {
	struct jnl_node_array nodes;
	struct jnl_edge_array edges;
	// holes
	jnl_vec2d *holes;
	u32 hlen, hcap;
	// regions
	jnl_vec2d *rcoords;
	i32 *rmarkers;
	f64 *rareas;
	u32 rlen, rcap;
};

void jnl_pslg_init(struct jnl_pslg *g);
void jnl_pslg_free(struct jnl_pslg *g);

u32 jnl_pslg_node_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker);
u32 jnl_pslg_node_add_v(struct jnl_pslg *g, jnl_vec2d v, i32 marker);
i32 jnl_pslg_node_find_nearest(const struct jnl_pslg *g, f64 x, f64 y);
i32 jnl_pslg_node_find_nearest_v(const struct jnl_pslg *g, jnl_vec2d v);
u32 jnl_pslg_node_find_or_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
                              f64 eps);
u32 jnl_pslg_node_find_or_add_v(struct jnl_pslg *g, jnl_vec2d v, i32 marker,
                                f64 eps);
i32 jnl_pslg_node_get(const struct jnl_pslg *g, u32 index, jnl_vec2d *out);

u32 jnl_pslg_edge_add(struct jnl_pslg *g, u32 p, u32 q, i32 marker);
u32 jnl_pslg_hole_add(struct jnl_pslg *g, f64 x, f64 y);
u32 jnl_pslg_hole_add_v(struct jnl_pslg *g, jnl_vec2d v);
u32 jnl_pslg_region_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
                        f64 max_area);
u32 jnl_pslg_region_add_v(struct jnl_pslg *g, jnl_vec2d v, i32 marker,
                          f64 max_area);

struct jnl_aabb jnl_pslg_bbox(const struct jnl_pslg *g);

void jnl_pslg_write(const struct jnl_pslg *g, FILE *file);

#endif
