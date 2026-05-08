#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

#include "geo2d.h"
#include "jnl/common.h"
#include "jnl/arena.h"

#define NODECAP_INIT (256)
#define HOLECAP_INIT (10)
#define REGIONCAP_INIT (10)

//
// Vector Implementation
//

jnl_vec2d jnl_vec2d_add(jnl_vec2d a, jnl_vec2d b)
{
	return (jnl_vec2d){
	    .x = a.x + b.x,
	    .y = a.y + b.y,
	};
}

jnl_vec2d jnl_vec2d_sub(jnl_vec2d a, jnl_vec2d b)
{
	return (jnl_vec2d){
	    .x = a.x - b.x,
	    .y = a.y - b.y,
	};
}

jnl_vec2d jnl_vec2d_scale(jnl_vec2d a, f64 s)
{
	return (jnl_vec2d){
	    .x = a.x * s,
	    .y = a.y * s,
	};
}

jnl_vec2d jnl_vec2d_normalise(jnl_vec2d a)
{
	return jnl_vec2d_scale(a, 1.0 / jnl_vec2d_len(a));
}

f64 jnl_vec2d_len(jnl_vec2d a) { return sqrt(jnl_vec2d_dist_sq(a)); }

f64 jnl_vec2d_dist_sq(jnl_vec2d a) { return (a.x * a.x) + (a.y * a.y); }

f64 jnl_vec2d_dot(jnl_vec2d a, jnl_vec2d b)
{
	return (a.x * b.x) + (a.x * b.y);
}

f64 jnl_vec2d_cross(jnl_vec2d a, jnl_vec2d b)
{
	return (a.x * b.y) - (a.y * b.x);
}

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

struct jnl_node_array jnl_node_array_compact(const struct jnl_node_array *ns,
                                             struct jnl_arena *arena)
{
	struct jnl_node_array out = {0};
	out.len = out.cap = ns->len;

	out.coords = ARENA_PUSH_ARRAY(arena, jnl_vec2d, ns->len);
	out.markers = ARENA_PUSH_ARRAY(arena, i32, ns->len);
	if (!out.coords || !out.markers) {
		return (struct jnl_node_array){0}; // arena full
	}

	memcpy(out.coords, ns->coords, ns->len * sizeof(jnl_vec2d));
	memcpy(out.markers, ns->markers, ns->len * sizeof(i32));
	return out;
}

u32 jnl_node_array_add(struct jnl_node_array *ns, f64 x, f64 y, i32 marker)
{
	if (ns->len >= ns->cap) {
		ns->cap *= 2;
		ns->coords = realloc(ns->coords, ns->cap * sizeof(*ns->coords));
		ns->markers = realloc(ns->markers, ns->cap * sizeof(*ns->markers));
	}

	ns->coords[ns->len].x = x;
	ns->coords[ns->len].y = y;
	ns->markers[ns->len] = marker;

	return ns->len++;
}

u32 jnl_node_array_add_v(struct jnl_node_array *ns, jnl_vec2d v, i32 marker)
{
	return jnl_node_array_add(ns, v.x, v.y, marker);
}

i32 jnl_node_array_find_nearest(const struct jnl_node_array *ns, f64 x, f64 y)
{
	if (ns->len == 0) {
		return GEO_NOT_FOUND;
	} else if (ns->len == 1) {
		return 0; // ie the index of the first
	}

	u32 mindex = 0;
	f64 dist_sq, mindist_sq, dx, dy = 0.0;

	// Using first node for initial minimum
	dx = (ns->coords[0].x - x), dy = (ns->coords[0].y - y);
	mindist_sq = (dx * dx) + (dy * dy);

	// Naive O(n) sweep
	for (u32 i = 1; i < ns->len; i++) {
		dx = (ns->coords[i].x - x);
		dy = (ns->coords[i].y - y);

		dist_sq = dx * dx + dy * dy;
		if (dist_sq < mindist_sq) {
			mindist_sq = dist_sq;
			mindex = i;
		}
	}

	return mindex;
}

i32 jnl_node_array_find_nearest_v(const struct jnl_node_array *ns, jnl_vec2d v)
{
	return jnl_node_array_find_nearest(ns, v.x, v.y);
}

u32 jnl_node_array_find_or_add(struct jnl_node_array *ns, f64 x, f64 y,
                               i32 marker, f64 eps)
{
	i32 idx = jnl_node_array_find_nearest(ns, x, y);
	if (idx >= GEO_OK) {
		jnl_vec2d out;
		jnl_node_array_get(ns, (u32)idx, &out);
		f64 dx = out.x - x, dy = out.y - y;
		if (dx * dx + dy * dy <= eps * eps) {
			return (u32)idx;
		}
	}

	return jnl_node_array_add(ns, x, y, marker);
}

u32 jnl_node_array_find_or_add_v(struct jnl_node_array *ns, jnl_vec2d v,
                                 i32 marker, f64 eps)
{
	return jnl_node_array_find_or_add(ns, v.x, v.y, marker, eps);
}

i32 jnl_node_array_get(const struct jnl_node_array *ns, u32 index,
                       jnl_vec2d *out)
{
	if (index >= ns->len) {
		return GEO_OOB;
	}

	*out = ns->coords[index];

	return GEO_OK;
}

struct jnl_aabb jnl_node_array_bbox(const struct jnl_node_array *ns)
{
	struct jnl_aabb box = {0};
	if (ns->len == 0) {
		return box;
	}

	u32 i = 0;

	if (ns->len % 2 != 0) {
		box.max_x = ns->coords[0].x, box.max_y = ns->coords[0].y;
		box.min_x = ns->coords[0].x, box.min_y = ns->coords[0].y;
		i++;
	}

	f64 x1, y1, x2, y2;

	for (; i < ns->len; i += 2) {
		x1 = ns->coords[i].x;
		x2 = ns->coords[i + 1].x;
		y1 = ns->coords[i].y;
		y2 = ns->coords[i + 1].y;

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
		fprintf(file, "%d %f %f %d\n", i, ns->coords[i].x, ns->coords[i].y,
		        ns->markers[i]);
	}
}

//
// Edges API
//

void jnl_edge_array_init(struct jnl_edge_array *es)
{
	es->cap = NODECAP_INIT;
	es->len = 0;
	es->ps = malloc(es->cap * sizeof(*es->ps));
	es->qs = malloc(es->cap * sizeof(*es->qs));
	es->markers = malloc(es->cap * sizeof(*es->markers));
}

void jnl_edge_array_free(struct jnl_edge_array *es)
{
	free(es->ps);
	free(es->qs);
	free(es->markers);
}

struct jnl_edge_array jnl_edge_array_compact(const struct jnl_edge_array *es,
                                             struct jnl_arena *arena)
{
	struct jnl_edge_array out = {0};
	out.len = out.cap = es->len;

	out.ps = ARENA_PUSH_ARRAY(arena, u32, es->len);
	out.qs = ARENA_PUSH_ARRAY(arena, u32, es->len);
	out.markers = ARENA_PUSH_ARRAY(arena, i32, es->len);
	if (!out.ps || !out.qs || !out.markers) {
		return (struct jnl_edge_array){0}; // arena full
	}

	memcpy(out.ps, es->ps, es->len * sizeof(u32));
	memcpy(out.qs, es->qs, es->len * sizeof(u32));
	memcpy(out.markers, es->markers, es->len * sizeof(i32));
	return out;
}

u32 jnl_edge_array_add(struct jnl_edge_array *es, u32 p, u32 q, i32 marker)
{
	if (es->len >= es->cap) {
		es->cap *= 2;
		es->ps = realloc(es->ps, es->cap * sizeof(*es->ps));
		es->qs = realloc(es->qs, es->cap * sizeof(*es->qs));
		es->markers = realloc(es->markers, es->cap * sizeof(*es->markers));
	}

	es->ps[es->len] = p;
	es->qs[es->len] = q;
	es->markers[es->len] = marker;

	return es->len++;
}

void jnl_edge_array_write(const struct jnl_edge_array *es, FILE *file)
{
	fprintf(file, "# Edges array (segments)\n");
	fprintf(file, "%d 1\n", es->len);
	for (u32 i = 0; i < es->len; i++) {
		fprintf(file, "%d %d %d %d\n", i, es->ps[i], es->qs[i], es->markers[i]);
	}

	if (es->len == 0) {
		fprintf(file, "# No edges present\n");
	}
}

//
// PSLG API
//

void jnl_pslg_init(struct jnl_pslg *g)
{
	jnl_node_array_init(&g->nodes);
	jnl_edge_array_init(&g->edges);

	g->hcap = HOLECAP_INIT;
	g->hlen = 0;
	g->holes = malloc(g->hcap * sizeof(*g->holes));

	g->rcap = REGIONCAP_INIT;
	g->rlen = 0;
	g->rcoords = malloc(g->rcap * sizeof(*g->rcoords));
	g->rmarkers = malloc(g->rcap * sizeof(*g->rmarkers));
	g->rareas = malloc(g->rcap * sizeof(*g->rareas));
}

void jnl_pslg_free(struct jnl_pslg *g)
{
	free(g->holes);

	free(g->rcoords);
	free(g->rmarkers);
	free(g->rareas);

	jnl_node_array_free(&g->nodes);
}

struct jnl_pslg jnl_pslg_compact(const struct jnl_pslg *g,
                                 struct jnl_arena *arena)
{
	struct jnl_pslg out = {0};
	out.nodes = jnl_node_array_compact(&g->nodes, arena);
	out.edges = jnl_edge_array_compact(&g->edges, arena);

	out.hlen = out.hcap = g->hlen;
	out.holes = ARENA_PUSH_ARRAY(arena, jnl_vec2d, g->hlen);
	if (!out.holes) {
		return (struct jnl_pslg){0};
	}
	memcpy(out.holes, g->holes, g->hlen * sizeof(jnl_vec2d));

	out.rlen = out.rcap = g->rlen;
	out.rcoords = ARENA_PUSH_ARRAY(arena, jnl_vec2d, g->rlen);
	out.rmarkers = ARENA_PUSH_ARRAY(arena, i32, g->rlen);
	out.rareas = ARENA_PUSH_ARRAY(arena, f64, g->rlen);
	if (!out.rcoords || !out.rmarkers || !out.rareas) {
		return (struct jnl_pslg){0};
	}

	memcpy(out.rcoords, g->rcoords, g->rlen * sizeof(jnl_vec2d));
	memcpy(out.rmarkers, g->rmarkers, g->rlen * sizeof(i32));
	memcpy(out.rareas, g->rareas, g->rlen * sizeof(f64));

	return out;
}

u32 jnl_pslg_node_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker)
{
	return jnl_node_array_add(&g->nodes, x, y, marker);
}

u32 jnl_pslg_node_add_v(struct jnl_pslg *g, jnl_vec2d v, i32 marker)
{
	return jnl_node_array_add(&g->nodes, v.x, v.y, marker);
}

i32 jnl_pslg_node_find_nearest(const struct jnl_pslg *g, f64 x, f64 y)
{
	return jnl_node_array_find_nearest(&g->nodes, x, y);
}

i32 jnl_pslg_node_find_nearest_v(const struct jnl_pslg *g, jnl_vec2d v)
{
	return jnl_node_array_find_nearest_v(&g->nodes, v);
}

u32 jnl_pslg_node_find_or_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
                              f64 eps)
{
	return jnl_node_array_find_or_add(&g->nodes, x, y, marker, eps);
}

u32 jnl_pslg_node_find_or_add_v(struct jnl_pslg *g, jnl_vec2d v, i32 marker,
                                f64 eps)
{
	return jnl_pslg_node_find_or_add(g, v.x, v.y, marker, eps);
}

i32 jnl_pslg_node_get(const struct jnl_pslg *g, u32 index, jnl_vec2d *out)
{
	return jnl_node_array_get(&g->nodes, index, out);
}

u32 jnl_pslg_edge_add(struct jnl_pslg *g, u32 p, u32 q, i32 marker)
{
	return jnl_edge_array_add(&g->edges, p, q, marker);
}

u32 jnl_pslg_hole_add(struct jnl_pslg *g, f64 x, f64 y)
{
	if (g->hlen >= g->hcap) {
		g->hcap *= 2;
		g->holes = realloc(g->holes, g->hcap * sizeof(*g->holes));
	}

	g->holes[g->hlen].x = x;
	g->holes[g->hlen].y = y;

	return g->hlen++;
}

u32 jnl_pslg_hole_add_v(struct jnl_pslg *g, jnl_vec2d v)
{
	return jnl_pslg_hole_add(g, v.x, v.y);
}

u32 jnl_pslg_region_add(struct jnl_pslg *g, f64 x, f64 y, i32 marker,
                        f64 max_area)
{
	if (g->rlen >= g->rcap) {
		g->rcap *= 2;
		g->rcoords = realloc(g->rcoords, g->rcap * sizeof(*g->rcoords));
		g->rmarkers = realloc(g->rmarkers, g->rcap * sizeof(*g->rmarkers));
		g->rareas = realloc(g->rareas, g->rcap * sizeof(*g->rareas));
	}

	g->rcoords[g->rlen].x = x;
	g->rcoords[g->rlen].y = y;
	g->rmarkers[g->rlen] = marker;
	g->rareas[g->rlen] = max_area;

	return g->rlen++;
}

u32 jnl_pslg_region_add_v(struct jnl_pslg *g, jnl_vec2d v, i32 marker,
                          f64 max_area)
{
	return jnl_pslg_region_add(g, v.x, v.y, marker, max_area);
}

struct jnl_aabb jnl_pslg_bbox(const struct jnl_pslg *g)
{
	return jnl_node_array_bbox(&g->nodes);
}

void jnl_pslg_write(const struct jnl_pslg *g, FILE *file)
{
	jnl_node_array_write(&g->nodes, file);

	fprintf(file, "# PSLG holes\n");
	fprintf(file, "%d\n", g->hlen);
	for (u32 i = 0; i < g->hlen; i++) {
		jnl_vec2d vec = g->holes[i];
		fprintf(file, "%d %f %f\n", i, vec.x, vec.y);
	}

	if (g->hlen == 0) {
		fprintf(file, "# No holes present\n");
	}

	if (g->rlen == 0) {
		return;
	}

	fprintf(file, "# PSLG regions (optional)\n");
	fprintf(file, "%d\n", g->rlen);
	for (u32 i = 0; i < g->rlen; i++) {
		jnl_vec2d vec = g->rcoords[i];
		fprintf(file, "%d %f %f %d %f\n", i, vec.x, vec.y, g->rmarkers[i],
		        g->rareas[i]);
	}
}
