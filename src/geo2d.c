#include <stdlib.h>
#include <stdio.h>

#include "geo2d.h"
#include "jnl/types.h"

#define NODECAP_INIT (256)
#define HOLECAP_INIT (10)
#define REGIONCAP_INIT (10)

//
// Nodes implementation
//

void jnl_node_array_init(struct jnl_node_array *ns)
{
	ns->cap = NODECAP_INIT;
	ns->len = 0;
	ns->coords = malloc(ns->cap * 2 * sizeof(*ns->coords));
	ns->markers = malloc(ns->cap * sizeof(*ns->markers));
}

void jnl_node_array_free(struct jnl_node_array *ns)
{
	free(ns->coords);
	free(ns->markers);
}

u32 jnl_node_array_add(struct jnl_node_array *ns, f64 x, f64 y, i32 marker)
{
	if (ns->len >= ns->cap) {
		ns->cap *= 2;
		ns->coords =
		    realloc(ns->coords, ns->cap * 2 * sizeof(*ns->coords));
		ns->markers =
		    realloc(ns->markers, ns->cap * sizeof(*ns->markers));
	}

	ns->coords[ns->len * 2] = x;
	ns->coords[ns->len * 2 + 1] = y;
	ns->markers[ns->len] = marker;

	return ns->len++;
}

i32 jnl_node_array_find_nearest(struct jnl_node_array *ns, f64 x, f64 y)
{
	if (ns->len == 0) {
		return GEO_NOT_FOUND;
	} else if (ns->len == 1) {
		return 0;	// ie the index of the first
	}

	u32 mindex = 0;
	f64 dist_sq, mindist_sq, dx, dy = 0.0;

	// Using first node for initial minimum
	dx = (ns->coords[0] - x), dy = (ns->coords[1] - y);
	mindist_sq = (dx * dx) + (dy * dy);

	// Naive O(n) sweep
	for (u32 i = 1; i < ns->len; i++) {
		dx = (ns->coords[i * 2] - x);
		dy = (ns->coords[i * 2 + 1] - y);

		dist_sq = dx * dx + dy * dy;
		if (dist_sq < mindist_sq) {
			mindist_sq = dist_sq;
			mindex = i;
		}
	}

	return mindex;
}

u32 jnl_node_array_find_or_add(struct jnl_node_array *ns, f64 x, f64 y,
			       i32 marker, f64 eps)
{
	i32 idx = jnl_node_array_find_nearest(ns, x, y);
	if (idx >= GEO_OK) {
		f64 nx, ny;
		jnl_node_array_get(ns, (u32) idx, &nx, &ny);
		f64 dx = nx - x, dy = ny - y;
		if (dx * dx + dy * dy <= eps * eps) {
			return (u32) idx;
		}
	}

	return jnl_node_array_add(ns, x, y, marker);
}

i32 jnl_node_array_get(struct jnl_node_array *ns, u32 index, f64 *x_out,
		       f64 *y_out)
{
	if (index >= ns->len) {
		return GEO_OOB;
	}

	*x_out = ns->coords[index * 2];
	*y_out = ns->coords[index * 2 + 1];

	return GEO_OK;
}

struct jnl_aabb jnl_node_array_bbox(const struct jnl_node_array *ns)
{
	struct jnl_aabb box = { 0 };
	if (ns->len == 0) {
		return box;
	}

	u32 i = 0;

	if (ns->len % 2 != 0) {
		box.max_x = ns->coords[0], box.max_y = ns->coords[1];
		box.min_x = ns->coords[0], box.min_y = ns->coords[1];
		i++;
	}

	f64 x1, y1, x2, y2;

	for (; i < ns->len; i += 2) {
		x1 = ns->coords[i * 2];
		x2 = ns->coords[(i + 1) * 2];
		y1 = ns->coords[(i * 2) + 1];
		y2 = ns->coords[((i + 1) * 2) + 1];

		// x tournament
		if (x1 > x2) {
			box.max_x = x1 > box.max_x ? x1 : box.max_x;
			box.min_x = x2 < box.min_x ? x2 : box.min_x;
		} else {
			box.max_x = x2 > box.max_x ? x2 : box.max_x;
			box.min_x = x1 < box.min_x ? x1 : box.min_x;
		}

		// y tournament
		if (y1 > y2) {
			box.max_y = y1 > box.max_y ? y1 : box.max_y;
			box.min_y = y2 < box.min_y ? y2 : box.min_y;
		} else {
			box.max_y = y2 > box.max_y ? y2 : box.max_y;
			box.min_y = y1 < box.min_y ? y1 : box.min_y;
		}
	}

	return box;
}

void jnl_node_array_write(const struct jnl_node_array *ns, FILE *file)
{
	fprintf(file, "# Node array\n");
	fprintf(file, "%d 2 0 1\n", ns->len);
	if (ns->len == 0) {
		fprintf(file, "# No nodes present\n");
		return;
	}

	for (u32 i = 0; i < ns->len; i++) {
		fprintf(file, "%d %f %f %d\n", i, ns->coords[i * 2],
			ns->coords[i * 2 + 1], ns->markers[i]);
	}

}

//
// PSLG API
//

void jnl_pslg_init(struct jnl_pslg *g)
{
	g->ecap = NODECAP_INIT;
	g->elen = 0;
	g->ps = malloc(g->ecap * sizeof(*g->ps));
	g->qs = malloc(g->ecap * sizeof(*g->qs));
	g->emarkers = malloc(g->ecap * sizeof(*g->emarkers));

	g->hcap = HOLECAP_INIT;
	g->hlen = 0;
	g->holes = malloc(g->hcap * sizeof(*g->holes));

	g->rcap = REGIONCAP_INIT;
	g->rlen = 0;
	g->rcoords = malloc(g->rcap * 2 * sizeof(*g->rcoords));
	g->rmarkers = malloc(g->rcap * sizeof(*g->rmarkers));
	g->rareas = malloc(g->rcap * sizeof(*g->rareas));

	jnl_node_array_init(&g->nodes);
}

void jnl_pslg_free(struct jnl_pslg *g)
{
	free(g->ps);
	free(g->qs);
	free(g->emarkers);

	free(g->holes);

	free(g->rcoords);
	free(g->rmarkers);
	free(g->rareas);

	jnl_node_array_free(&g->nodes);
}

u32 jnl_pslg_node_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker)
{
	return jnl_node_array_add(&g->nodes, x, y, marker);
}

i32 jnl_pslg_node_find_nearest(struct jnl_pslg *g, f64 x, f64 y)
{
	return jnl_node_array_find_nearest(&g->nodes, x, y);
}

u32 jnl_pslg_node_find_or_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
			      f64 eps)
{
	return jnl_node_array_find_or_add(&g->nodes, x, y, eps, marker);
}

i32 jnl_pslg_node_get(struct jnl_pslg *g, u32 index, f64 *x_out,
		      f64 *y_out)
{
	return jnl_node_array_get(&g->nodes, index, x_out, y_out);
}

u32 jnl_pslg_edge_add(struct jnl_pslg *g, u32 p, u32 q, i32 marker)
{
	if (g->elen >= g->ecap) {
		g->ecap *= 2;
		g->ps = realloc(g->ps, g->ecap * sizeof(*g->ps));
		g->qs = realloc(g->qs, g->ecap * sizeof(*g->qs));
		g->emarkers =
		    realloc(g->emarkers, g->ecap * sizeof(*g->emarkers));
	}

	g->ps[g->elen] = p;
	g->qs[g->elen] = q;
	g->emarkers[g->elen] = marker;

	return g->elen++;
}

u32 jnl_pslg_hole_add(struct jnl_pslg *g, f64 x, f64 y)
{
	if (g->hlen >= g->hcap) {
		g->hcap *= 2;
		g->holes =
		    realloc(g->holes, g->hcap * 2 * sizeof(*g->holes));
	}

	g->holes[g->hlen * 2] = x;
	g->holes[g->hlen * 2 + 1] = y;

	return g->hlen++;
}

u32 jnl_pslg_region_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
			f64 max_area)
{
	if (g->rlen >= g->rcap) {
		g->rcap *= 2;
		g->rcoords =
		    realloc(g->rcoords, g->rcap * sizeof(*g->rcoords));
		g->rmarkers =
		    realloc(g->rmarkers, g->rcap * sizeof(*g->rmarkers));
		g->rareas =
		    realloc(g->rareas, g->rcap * sizeof(*g->rareas));
	}

	g->rcoords[g->rlen * 2] = x;
	g->rcoords[g->rlen * 2 + 1] = y;
	g->rmarkers[g->rlen] = marker;
	g->rareas[g->rlen] = max_area;

	return g->rlen++;
}

struct jnl_aabb jnl_pslg_bbox(const struct jnl_pslg *g)
{
	return jnl_node_array_bbox(&g->nodes);
}

void jnl_pslg_write(const struct jnl_pslg *g, FILE *file)
{
	jnl_node_array_write(&g->nodes, file);

	fprintf(file, "# PSLG edges (segments)\n");
	fprintf(file, "%d 1\n", g->elen);
	for (u32 i = 0; i < g->elen; i++) {
		fprintf(file, "%d %d %d %d\n", i, g->ps[i], g->qs[i],
			g->emarkers[i]);
	}

	if (g->elen == 0) {
		fprintf(file, "# No edges present\n");
	}

	fprintf(file, "# PSLG holes\n");
	fprintf(file, "%d\n", g->hlen);
	for (u32 i = 0; i < g->hlen; i++) {
		fprintf(file, "%d %f %f\n", i, g->holes[i * 2],
			g->holes[i * 2 + 1]);
	}

	if (g->elen == 0) {
		fprintf(file, "# No holes present\n");
	}

	if (g->rlen == 0) {
		return;
	}

	fprintf(file, "# PSLG regions (optional)\n");
	fprintf(file, "%d\n", g->rlen);
	for (u32 i = 0; i < g->rlen; i++) {
		fprintf(file, "%d %f %f %d %f\n", i, g->rcoords[i * 2],
			g->rcoords[i * 2 + 1], g->rmarkers[i],
			g->rareas[i]);
	}
}
