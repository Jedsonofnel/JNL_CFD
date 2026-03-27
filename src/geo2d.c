#include <stdlib.h>
#include <stdio.h>

#include "geo2d.h"
#include "jn/types.h"

#define NODECAP_INIT (256)
#define HOLECAP_INIT (10)
#define REGIONCAP_INIT (10)

//
// Nodes implementation
//

void node_array_init(node_array *ns)
{
	ns->cap = NODECAP_INIT;
	ns->len = 0;
	ns->coords = malloc(ns->cap * 2 * sizeof(*ns->coords));
	ns->markers = malloc(ns->cap * sizeof(*ns->markers));
}

void node_array_free(node_array *ns)
{
	free(ns->coords);
	free(ns->markers);
}

u32 node_array_add(node_array *ns, f64 x, f64 y, i32 marker)
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

i32 node_array_find_nearest(node_array *ns, f64 x, f64 y)
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

u32 node_array_find_or_add(node_array *ns, f64 x, f64 y, i32 marker,
			   f64 eps)
{
	i32 idx = node_array_find_nearest(ns, x, y);
	if (idx >= GEO_OK) {
		f64 nx, ny;
		node_array_get(ns, (u32) idx, &nx, &ny);
		f64 dx = nx - x, dy = ny - y;
		if (dx * dx + dy * dy <= eps * eps) {
			return (u32) idx;
		}
	}

	return node_array_add(ns, x, y, marker);
}

i32 node_array_get(node_array *ns, u32 index, f64 *x_out, f64 *y_out)
{
	if (index >= ns->len) {
		return GEO_OOB;
	}

	*x_out = ns->coords[index * 2];
	*y_out = ns->coords[index * 2 + 1];

	return GEO_OK;
}

void node_array_write(FILE *file, const node_array *ns)
{
	fprintf(file, "# Node array\n");
	fprintf(file, "%d 2 0 1\n", ns->len);
	for (u32 i = 0; i < ns->len; i++) {
		fprintf(file, "%d %f %f %d\n", i, ns->coords[i * 2],
			ns->coords[i * 2 + 1], ns->markers[i]);
	}
}

//
// PSLG API
//

void pslg_init(pslg *g)
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

	node_array_init(&g->nodes);
}

void pslg_free(pslg *g)
{
	free(g->ps);
	free(g->qs);
	free(g->emarkers);

	free(g->holes);

	free(g->rcoords);
	free(g->rmarkers);
	free(g->rareas);

	node_array_free(&g->nodes);
}

u32 pslg_node_add(pslg *g, f64 x, f64 y, i32 marker)
{
	return node_array_add(&g->nodes, x, y, marker);
}

i32 pslg_node_find_nearest(pslg *g, f64 x, f64 y)
{
	return node_array_find_nearest(&g->nodes, x, y);
}

u32 pslg_node_find_or_add(pslg *g, f64 x, f64 y, i32 marker, f64 eps)
{
	return node_array_find_or_add(&g->nodes, x, y, eps, marker);
}

i32 pslg_node_get(pslg *g, u32 index, f64 *x_out, f64 *y_out)
{
	return node_array_get(&g->nodes, index, x_out, y_out);
}

u32 pslg_edge_add(pslg *g, u32 p, u32 q, i32 marker)
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

u32 pslg_hole_add(pslg *g, f64 x, f64 y)
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

u32 pslg_region_add(pslg *g, f64 x, f64 y, i32 marker, f64 max_area)
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

void pslg_write(FILE *file, const pslg *g)
{
	node_array_write(file, &g->nodes);

	fprintf(file, "# PSLG edges (segments)\n");
	fprintf(file, "%d 1\n", g->elen);
	for (u32 i = 0; i < g->elen; i++) {
		fprintf(file, "%d %d %d %d\n", i, g->ps[i], g->qs[i],
			g->emarkers[i]);
	}

	fprintf(file, "# PSLG holes\n");
	fprintf(file, "%d\n", g->hlen);
	for (u32 i = 0; i < g->hlen; i++) {
		fprintf(file, "%d %f %f\n", i, g->holes[i * 2],
			g->holes[i * 2 + 1]);
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
