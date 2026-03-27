#ifndef JNL_GEO2D_H
#define JNL_GEO2D_H

#include <stdio.h>

#include "jnl/types.h"

#define GEO_NOT_FOUND (-1)
#define GEO_OOB (-2)
#define GEO_OK (0)

//
// Nodes API
//

struct jnl_node_array {
  f64 *coords;
  i32 *markers;
  u32 len, cap;
};

struct jnl_aabb {
  f64 max_x, max_y;
  f64 min_x, min_y;
};

void jnl_node_array_init(struct jnl_node_array *ns);
void jnl_node_array_free(struct jnl_node_array *ns);

u32 jnl_node_array_add(struct jnl_node_array *ns, f64 x, f64 y, i32 marker);
i32 jnl_node_array_find_nearest(struct jnl_node_array *ns, f64 x, f64 y);
u32 jnl_node_array_find_or_add(struct jnl_node_array *ns, f64 x, f64 y,
                               i32 marker, f64 eps);
i32 jnl_node_array_get(struct jnl_node_array *ns, u32 index, f64 *x_out,
                       f64 *y_out);

struct jnl_aabb jnl_node_array_bbox(const struct jnl_node_array *ns);

void jnl_node_array_write(const struct jnl_node_array *ns, FILE *file);

//
// PSLG API
//

struct jnl_pslg {
  // nodes
  struct jnl_node_array nodes;
  // edges
  u32 *ps, *qs;
  i32 *emarkers;
  u32 elen, ecap;
  // holes
  f64 *holes;
  u32 hlen, hcap;
  // regions
  f64 *rcoords;
  i32 *rmarkers;
  f64 *rareas;
  u32 rlen, rcap;
};

void jnl_pslg_init(struct jnl_pslg *g);
void jnl_pslg_free(struct jnl_pslg *g);

u32 jnl_pslg_node_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker);
i32 jnl_pslg_node_find_nearest(struct jnl_pslg *g, f64 x, f64 y);
u32 jnl_pslg_node_find_or_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
                              f64 eps);
i32 jnl_pslg_node_get(struct jnl_pslg *g, u32 index, f64 *x_out, f64 *y_out);

u32 jnl_pslg_edge_add(struct jnl_pslg *g, u32 p, u32 q, i32 marker);
u32 jnl_pslg_hole_add(struct jnl_pslg *g, f64 x, f64 y);
u32 jnl_pslg_region_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
                        f64 max_area);

struct jnl_aabb jnl_pslg_bbox(const struct jnl_pslg *ns);

void jnl_pslg_write(const struct jnl_pslg *g, FILE *file);

#endif
