#ifndef JNL_GEO2D_H
#define JNL_GEO2D_H

#include <stdio.h>

#include "jn/types.h"

#define GEO_NOT_FOUND (-1)
#define GEO_OOB (-2)
#define GEO_OK (0)

//
// Nodes API
//

typedef struct node_array {
  f64 *coords;
  i32 *markers;
  u32 len, cap;
} node_array;

void node_array_init(node_array *ns);
void node_array_free(node_array *ns);

u32 node_array_add(node_array *ns, f64 x, f64 y, i32 marker);
i32 node_array_find_nearest(node_array *ns, f64 x, f64 y);
u32 node_array_find_or_add(node_array *ns, f64 x, f64 y, i32 marker, f64 eps);
i32 node_array_get(node_array *ns, u32 index, f64 *x_out, f64 *y_out);

void node_array_write(FILE *file, const node_array *ns);

//
// PSLG API
//

typedef struct pslg {
  // nodes
  node_array nodes;
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
} pslg;

void pslg_init(pslg *g);
void pslg_free(pslg *g);

u32 pslg_node_add(pslg *g, f64 x, f64 y, i32 marker);
i32 pslg_node_find_nearest(pslg *g, f64 x, f64 y);
u32 pslg_node_find_or_add(pslg *g, f64 x, f64 y, i32 marker, f64 eps);
i32 pslg_node_get(pslg *g, u32 index, f64 *x_out, f64 *y_out);

u32 pslg_edge_add(pslg *g, u32 p, u32 q, i32 marker);
u32 pslg_hole_add(pslg *g, f64 x, f64 y);
u32 pslg_region_add(pslg *g, f64 x, f64 y, i32 marker, f64 max_area);

void pslg_write(FILE *file, const pslg *g);

#endif
