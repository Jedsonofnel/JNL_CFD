#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "triangle.h"
#include "triangle_api.h"

#include "mesh2d/trimesh2d.h"

//
// Small helpers
//

static void tri_copy_name(char dst[JNL_PMSH2D_NAME_CAP], const char *src)
{
	if (!dst)
		return;

	if (!src) {
		dst[0] = '\0';
		return;
	}

	strncpy(dst, src, JNL_PMSH2D_NAME_CAP - 1);
	dst[JNL_PMSH2D_NAME_CAP - 1] = '\0';
}

static void tri_default_name(char dst[JNL_PMSH2D_NAME_CAP], const char *prefix,
                             i32 marker)
{
	snprintf(dst, JNL_PMSH2D_NAME_CAP, "%s_%d", prefix, marker);
	dst[JNL_PMSH2D_NAME_CAP - 1] = '\0';
}

//
// Options
//

struct jnl_tri_opts jnl_tri_opts_default(void)
{
	return (struct jnl_tri_opts){
	    .preserve_segments = true,
	    .conforming_delaunay = false,

	    .quality_mode = JNL_TRIANGLE_QUALITY_MIN_ANGLE,
	    .min_angle_deg = 20.0,

	    .use_global_max_area = false,
	    .global_max_area = 0.0,

	    .use_region_areas = true,

	    .zero_based_numbering = true,

	    .quiet = true,
	    .verbose = false,
	};
}

struct jnl_tri_opts jnl_tri_opts_set_min_angle(struct jnl_tri_opts opts,
                                               f64 min_angle_deg)
{
	if (min_angle_deg > 0.0) {
		opts.quality_mode = JNL_TRIANGLE_QUALITY_MIN_ANGLE;
		opts.min_angle_deg = min_angle_deg;
	} else {
		opts.quality_mode = JNL_TRIANGLE_QUALITY_NONE;
		opts.min_angle_deg = 0.0;
	}

	return opts;
}

struct jnl_tri_opts jnl_tri_opts_set_global_max_area(struct jnl_tri_opts opts,
                                                     f64 max_area)
{
	if (max_area > 0.0) {
		opts.use_global_max_area = true;
		opts.global_max_area = max_area;
	} else {
		opts.use_global_max_area = false;
		opts.global_max_area = 0.0;
	}

	return opts;
}

struct jnl_tri_opts jnl_tri_opts_set_cell_count(struct jnl_tri_opts opts,
                                                const struct jnl_pslg *pslg,
                                                i32 target_cells)
{
	if (!pslg || target_cells <= 0)
		return opts;

	struct jnl_aabb bbox = jnl_pslg_bbox(pslg);

	f64 w = bbox.max_x - bbox.min_x;
	f64 h = bbox.max_y - bbox.min_y;
	f64 bbox_area = w * h;

	f64 target_area = (bbox_area * 0.9) / (f64)target_cells;

	return jnl_tri_opts_set_global_max_area(opts, target_area);
}

struct jnl_tri_opts jnl_tri_opts_set_resolution(struct jnl_tri_opts opts,
                                                const struct jnl_pslg *pslg,
                                                f64 resolution)
{
	if (!pslg || resolution <= 0.0)
		return opts;

	struct jnl_aabb bbox = jnl_pslg_bbox(pslg);

	f64 w = bbox.max_x - bbox.min_x;
	f64 h = bbox.max_y - bbox.min_y;
	f64 scale = (w < h) ? w : h;

	f64 edge = resolution * scale;
	f64 target_area = 0.4330127018922193 * edge * edge;

	return jnl_tri_opts_set_global_max_area(opts, target_area);
}

struct jnl_tri_opts jnl_tri_opts_enable_region_areas(struct jnl_tri_opts opts,
                                                     bool enabled)
{
	opts.use_region_areas = enabled;
	return opts;
}

struct jnl_tri_opts
jnl_tri_opts_set_conforming_delaunay(struct jnl_tri_opts opts, bool enabled)
{
	opts.conforming_delaunay = enabled;
	return opts;
}

struct jnl_tri_opts jnl_tri_opts_set_quiet(struct jnl_tri_opts opts,
                                           bool enabled)
{
	opts.quiet = enabled;
	return opts;
}

//
// Marker maps
//

static const struct jnl_tri_marker_name *
tri_marker_map_find_entry(const struct jnl_tri_marker_map *map, i32 marker)
{
	if (!map)
		return NULL;

	for (u32 i = 0; i < map->len; i++) {
		if (map->data[i].marker == marker)
			return &map->data[i];
	}

	return NULL;
}

static enum jnl_mesh_err tri_marker_map_reserve(struct jnl_tri_marker_map *map,
                                                u32 min_cap)
{
	if (map->cap >= min_cap)
		return JNL_MESH_OK;

	u32 new_cap = map->cap ? map->cap * 2 : 4;
	while (new_cap < min_cap)
		new_cap *= 2;

	struct jnl_tri_marker_name *new_data =
	    realloc(map->data, sizeof(*map->data) * new_cap);

	if (!new_data)
		return JNL_MESH_ERR_ALLOC;

	map->data = new_data;
	map->cap = new_cap;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_marker_map_add(struct jnl_tri_marker_map *map,
                                            i32 marker, const char *name)
{
	if (!map || !name || name[0] == '\0')
		return JNL_MESH_ERR_INVALID_INPUT;

	if (tri_marker_map_find_entry(map, marker))
		return JNL_MESH_ERR_DUPLICATE_MARKER;

	enum jnl_mesh_err err = tri_marker_map_reserve(map, map->len + 1);
	if (err != JNL_MESH_OK)
		return err;

	struct jnl_tri_marker_name *entry = &map->data[map->len++];

	entry->marker = marker;
	tri_copy_name(entry->name, name);

	return JNL_MESH_OK;
}

static void tri_marker_map_free(struct jnl_tri_marker_map *map)
{
	if (!map)
		return;

	free(map->data);
	map->data = NULL;
	map->len = 0;
	map->cap = 0;
}

static bool tri_marker_map_contains(const struct jnl_tri_marker_map *map,
                                    i32 marker)
{
	return tri_marker_map_find_entry(map, marker) != NULL;
}

static const char *
tri_marker_map_find_name(const struct jnl_tri_marker_map *map, i32 marker)
{
	const struct jnl_tri_marker_name *entry =
	    tri_marker_map_find_entry(map, marker);

	return entry ? entry->name : NULL;
}

//
// Tags
//

struct jnl_tri_mesh_spec jnl_tri_mesh_spec_default(void)
{
	struct jnl_tri_mesh_spec spec;

	spec.opts = jnl_tri_opts_default();
	jnl_tri_tags_init(&spec.tags);

	return spec;
}

void jnl_tri_tags_init(struct jnl_tri_tags *tags)
{
	if (!tags)
		return;

	memset(tags, 0, sizeof(*tags));

	tags->require_named_patches = true;
	tags->require_named_baffles = true;
	tags->require_named_regions = false;
}

void jnl_tri_tags_free(struct jnl_tri_tags *tags)
{
	if (!tags)
		return;

	tri_marker_map_free(&tags->patches);
	tri_marker_map_free(&tags->baffles);
	tri_marker_map_free(&tags->regions);

	tags->require_named_patches = false;
	tags->require_named_baffles = false;
	tags->require_named_regions = false;
}

enum jnl_mesh_err jnl_tri_tags_add_patch(struct jnl_tri_tags *tags, i32 marker,
                                         const char *name)
{
	if (!tags)
		return JNL_MESH_ERR_INVALID_INPUT;

	return tri_marker_map_add(&tags->patches, marker, name);
}

enum jnl_mesh_err jnl_tri_tags_add_baffle(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name)
{
	if (!tags)
		return JNL_MESH_ERR_INVALID_INPUT;

	return tri_marker_map_add(&tags->baffles, marker, name);
}

enum jnl_mesh_err jnl_tri_tags_add_region(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name)
{
	if (!tags)
		return JNL_MESH_ERR_INVALID_INPUT;

	return tri_marker_map_add(&tags->regions, marker, name);
}

const char *jnl_tri_tags_find_patch(const struct jnl_tri_tags *tags, i32 marker)
{
	if (!tags)
		return NULL;

	return tri_marker_map_find_name(&tags->patches, marker);
}

const char *jnl_tri_tags_find_baffle(const struct jnl_tri_tags *tags,
                                     i32 marker)
{
	if (!tags)
		return NULL;

	return tri_marker_map_find_name(&tags->baffles, marker);
}

const char *jnl_tri_tags_find_region(const struct jnl_tri_tags *tags,
                                     i32 marker)
{
	if (!tags)
		return NULL;

	return tri_marker_map_find_name(&tags->regions, marker);
}

bool jnl_tri_tags_is_baffle_marker(const struct jnl_tri_tags *tags, i32 marker)
{
	return tags && tri_marker_map_contains(&tags->baffles, marker);
}

//
// Triangle IO lifecycle
//

static void triangleio_init(triangleio *io)
{
	if (!io)
		return;

	memset(io, 0, sizeof(*io));
}

static void triangleio_free_input(triangleio *io)
{
	if (!io)
		return;

	free(io->pointlist);
	free(io->pointattributelist);
	free(io->pointmarkerlist);
	free(io->trianglelist);
	free(io->triangleattributelist);
	free(io->trianglearealist);
	free(io->neighborlist);
	free(io->segmentlist);
	free(io->segmentmarkerlist);
	free(io->holelist);
	free(io->regionlist);
	free(io->edgelist);
	free(io->edgemarkerlist);

	triangleio_init(io);
}

static void triangleio_free_output(triangleio *io)
{
	if (!io)
		return;

	if (io->pointlist)
		triangle_free(io->pointlist);
	if (io->pointattributelist)
		triangle_free(io->pointattributelist);
	if (io->pointmarkerlist)
		triangle_free(io->pointmarkerlist);
	if (io->trianglelist)
		triangle_free(io->trianglelist);
	if (io->triangleattributelist)
		triangle_free(io->triangleattributelist);
	if (io->trianglearealist)
		triangle_free(io->trianglearealist);
	if (io->neighborlist)
		triangle_free(io->neighborlist);
	if (io->segmentlist)
		triangle_free(io->segmentlist);
	if (io->segmentmarkerlist)
		triangle_free(io->segmentmarkerlist);
	if (io->holelist)
		triangle_free(io->holelist);
	if (io->regionlist)
		triangle_free(io->regionlist);
	if (io->edgelist)
		triangle_free(io->edgelist);
	if (io->edgemarkerlist)
		triangle_free(io->edgemarkerlist);

	triangleio_init(io);
}

//
// Triangle input
//

static enum jnl_mesh_err
tri_validate_inputs(const struct jnl_pslg *pslg,
                    const struct jnl_tri_mesh_spec *spec)
{
	if (!pslg || !spec)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (pslg->nodes.len < 3)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (spec->opts.min_angle_deg < 0.0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (spec->opts.global_max_area < 0.0)
		return JNL_MESH_ERR_INVALID_INPUT;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_append_switch(char *buf, size_t buf_len,
                                           size_t *pos, const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);

	int n = vsnprintf(buf + *pos, buf_len - *pos, fmt, args);

	va_end(args);

	if (n < 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (*pos + (size_t)n >= buf_len)
		return JNL_MESH_ERR_INVALID_INPUT;

	*pos += (size_t)n;
	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_build_switches(const struct jnl_tri_opts *opts,
                                            char *buf, size_t buf_len)
{
	if (!opts || !buf || buf_len == 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	size_t pos = 0;
	buf[0] = '\0';

	/*
	 * p: PSLG input.
	 * A: propagate region attributes.
	 * e: output edges and edge markers.
	 */
	if (tri_append_switch(buf, buf_len, &pos, "pAe") != JNL_MESH_OK)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (opts->zero_based_numbering) {
		if (tri_append_switch(buf, buf_len, &pos, "z") != JNL_MESH_OK)
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (opts->quiet) {
		if (tri_append_switch(buf, buf_len, &pos, "Q") != JNL_MESH_OK)
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (opts->verbose) {
		if (tri_append_switch(buf, buf_len, &pos, "V") != JNL_MESH_OK)
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (opts->conforming_delaunay) {
		if (tri_append_switch(buf, buf_len, &pos, "D") != JNL_MESH_OK)
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (opts->quality_mode == JNL_TRIANGLE_QUALITY_MIN_ANGLE) {
		if (opts->min_angle_deg > 0.0) {
			if (tri_append_switch(buf, buf_len, &pos, "q%.17f",
			                      opts->min_angle_deg) != JNL_MESH_OK)
				return JNL_MESH_ERR_INVALID_INPUT;
		} else {
			if (tri_append_switch(buf, buf_len, &pos, "q") != JNL_MESH_OK)
				return JNL_MESH_ERR_INVALID_INPUT;
		}
	}

	if (opts->use_global_max_area) {
		if (tri_append_switch(buf, buf_len, &pos, "a%.17f",
		                      opts->global_max_area) != JNL_MESH_OK)
			return JNL_MESH_ERR_INVALID_INPUT;
	} else if (opts->use_region_areas) {
		if (tri_append_switch(buf, buf_len, &pos, "a") != JNL_MESH_OK)
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_fill_points(const struct jnl_pslg *pslg,
                                         triangleio *in)
{
	in->numberofpoints = (int)pslg->nodes.len;
	in->numberofpointattributes = 0;

	in->pointlist = malloc(sizeof(REAL) * 2 * pslg->nodes.len);
	in->pointmarkerlist = malloc(sizeof(int) * pslg->nodes.len);

	if (!in->pointlist || !in->pointmarkerlist)
		return JNL_MESH_ERR_ALLOC;

	for (u32 i = 0; i < pslg->nodes.len; i++) {
		in->pointlist[2 * i + 0] = (REAL)pslg->nodes.coords[i].x;
		in->pointlist[2 * i + 1] = (REAL)pslg->nodes.coords[i].y;
		in->pointmarkerlist[i] = (int)pslg->nodes.markers[i];
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_fill_segments(const struct jnl_pslg *pslg,
                                           triangleio *in)
{
	in->numberofsegments = (int)pslg->edges.len;

	if (pslg->edges.len == 0)
		return JNL_MESH_OK;

	in->segmentlist = malloc(sizeof(int) * 2 * pslg->edges.len);
	in->segmentmarkerlist = malloc(sizeof(int) * pslg->edges.len);

	if (!in->segmentlist || !in->segmentmarkerlist)
		return JNL_MESH_ERR_ALLOC;

	for (u32 i = 0; i < pslg->edges.len; i++) {
		in->segmentlist[2 * i + 0] = (int)pslg->edges.ps[i];
		in->segmentlist[2 * i + 1] = (int)pslg->edges.qs[i];
		in->segmentmarkerlist[i] = (int)pslg->edges.markers[i];
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_fill_holes(const struct jnl_pslg *pslg,
                                        triangleio *in)
{
	in->numberofholes = (int)pslg->hlen;

	if (pslg->hlen == 0)
		return JNL_MESH_OK;

	in->holelist = malloc(sizeof(REAL) * 2 * pslg->hlen);
	if (!in->holelist)
		return JNL_MESH_ERR_ALLOC;

	for (u32 i = 0; i < pslg->hlen; i++) {
		in->holelist[2 * i + 0] = (REAL)pslg->holes[i].x;
		in->holelist[2 * i + 1] = (REAL)pslg->holes[i].y;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_fill_regions(const struct jnl_pslg *pslg,
                                          const struct jnl_tri_opts *opts,
                                          triangleio *in)
{
	in->numberofregions = (int)pslg->rlen;

	if (pslg->rlen == 0)
		return JNL_MESH_OK;

	in->regionlist = malloc(sizeof(REAL) * 4 * pslg->rlen);
	if (!in->regionlist)
		return JNL_MESH_ERR_ALLOC;

	for (u32 i = 0; i < pslg->rlen; i++) {
		in->regionlist[4 * i + 0] = (REAL)pslg->rcoords[i].x;
		in->regionlist[4 * i + 1] = (REAL)pslg->rcoords[i].y;
		in->regionlist[4 * i + 2] = (REAL)pslg->rmarkers[i];
		in->regionlist[4 * i + 3] =
		    opts->use_region_areas ? (REAL)pslg->rareas[i] : (REAL)0.0;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_pslg_to_triangle_input(const struct jnl_pslg *pslg,
                           const struct jnl_tri_opts *opts, triangleio *in)
{
	enum jnl_mesh_err err;

	if (!pslg || !opts || !in)
		return JNL_MESH_ERR_INVALID_INPUT;

	triangleio_init(in);

	err = tri_fill_points(pslg, in);
	if (err != JNL_MESH_OK)
		return err;

	err = tri_fill_segments(pslg, in);
	if (err != JNL_MESH_OK)
		return err;

	err = tri_fill_holes(pslg, in);
	if (err != JNL_MESH_OK)
		return err;

	err = tri_fill_regions(pslg, opts, in);
	if (err != JNL_MESH_OK)
		return err;

	return JNL_MESH_OK;
}

//
// Edge adjacency from Triangle output
//

struct tri_edge_adj {
	i32 a, b;

	i32 cell0, cell1;
	i32 marker;
};

struct tri_edge_list {
	struct tri_edge_adj *data;
	i32 len, cap;
};

static void tri_edge_key(i32 v0, i32 v1, i32 *a, i32 *b)
{
	if (v0 < v1) {
		*a = v0;
		*b = v1;
	} else {
		*a = v1;
		*b = v0;
	}
}

static void tri_edge_list_init(struct tri_edge_list *edges)
{
	memset(edges, 0, sizeof(*edges));
}

static void tri_edge_list_free(struct tri_edge_list *edges)
{
	if (!edges)
		return;

	free(edges->data);
	tri_edge_list_init(edges);
}

static enum jnl_mesh_err tri_edge_list_reserve(struct tri_edge_list *edges,
                                               i32 min_cap)
{
	if (edges->cap >= min_cap)
		return JNL_MESH_OK;

	i32 new_cap = edges->cap ? edges->cap * 2 : 64;
	while (new_cap < min_cap)
		new_cap *= 2;

	struct tri_edge_adj *new_data =
	    realloc(edges->data, sizeof(*edges->data) * new_cap);

	if (!new_data)
		return JNL_MESH_ERR_ALLOC;

	edges->data = new_data;
	edges->cap = new_cap;

	return JNL_MESH_OK;
}

static i32 tri_edge_list_find(const struct tri_edge_list *edges, i32 a, i32 b)
{
	for (i32 i = 0; i < edges->len; i++) {
		if (edges->data[i].a == a && edges->data[i].b == b)
			return i;
	}

	return -1;
}

static enum jnl_mesh_err
tri_edge_list_add_or_update(struct tri_edge_list *edges, i32 v0, i32 v1,
                            i32 cell)
{
	i32 a, b;
	tri_edge_key(v0, v1, &a, &b);

	i32 found = tri_edge_list_find(edges, a, b);

	if (found >= 0) {
		if (edges->data[found].cell1 >= 0)
			return JNL_MESH_ERR_NONMANIFOLD_EDGE;

		edges->data[found].cell1 = cell;
		return JNL_MESH_OK;
	}

	enum jnl_mesh_err err = tri_edge_list_reserve(edges, edges->len + 1);
	if (err != JNL_MESH_OK)
		return err;

	struct tri_edge_adj *edge = &edges->data[edges->len++];

	edge->a = a;
	edge->b = b;
	edge->cell0 = cell;
	edge->cell1 = -1;
	edge->marker = 0;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_build_edge_adjacency(const triangleio *out,
                                                  struct tri_edge_list *edges)
{
	if (!out || !out->trianglelist || out->numberoftriangles <= 0)
		return JNL_MESH_ERR_IMPORT_FAILED;

	for (i32 c = 0; c < out->numberoftriangles; c++) {
		const int *tri = &out->trianglelist[c * out->numberofcorners];

		i32 v0 = tri[0];
		i32 v1 = tri[1];
		i32 v2 = tri[2];

		enum jnl_mesh_err err;

		err = tri_edge_list_add_or_update(edges, v0, v1, c);
		if (err != JNL_MESH_OK)
			return err;

		err = tri_edge_list_add_or_update(edges, v1, v2, c);
		if (err != JNL_MESH_OK)
			return err;

		err = tri_edge_list_add_or_update(edges, v2, v0, c);
		if (err != JNL_MESH_OK)
			return err;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_apply_edge_markers(const triangleio *out,
                                                struct tri_edge_list *edges)
{
	if (!out || !edges)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!out->edgelist || !out->edgemarkerlist || out->numberofedges <= 0)
		return JNL_MESH_ERR_IMPORT_FAILED;

	for (i32 e = 0; e < out->numberofedges; e++) {
		i32 v0 = out->edgelist[2 * e + 0];
		i32 v1 = out->edgelist[2 * e + 1];

		i32 a, b;
		tri_edge_key(v0, v1, &a, &b);

		i32 found = tri_edge_list_find(edges, a, b);
		if (found < 0)
			return JNL_MESH_ERR_EDGE_NOT_FOUND;

		edges->data[found].marker = (i32)out->edgemarkerlist[e];
	}

	return JNL_MESH_OK;
}

//
// Desc name helpers
//

static enum jnl_mesh_err
desc_copy_marker_map(struct jnl_pmsh2d_desc_name **out_names, i32 *out_n_names,
                     const struct jnl_tri_marker_map *map)
{
	if (!out_names || !out_n_names || !map)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_names = NULL;
	*out_n_names = 0;

	if (map->len == 0)
		return JNL_MESH_OK;

	struct jnl_pmsh2d_desc_name *names = calloc(map->len, sizeof(*names));
	if (!names)
		return JNL_MESH_ERR_ALLOC;

	for (u32 i = 0; i < map->len; i++) {
		names[i].marker = map->data[i].marker;
		tri_copy_name(names[i].name, map->data[i].name);
	}

	*out_names = names;
	*out_n_names = (i32)map->len;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err desc_add_region_name(struct jnl_polymesh2d_desc *desc,
                                              i32 marker, const char *name)
{
	for (i32 i = 0; i < desc->n_region_names; i++) {
		if (desc->region_names[i].marker == marker)
			return JNL_MESH_OK;
	}

	struct jnl_pmsh2d_desc_name *new_names =
	    realloc(desc->region_names, sizeof(*desc->region_names) *
	                                    (size_t)(desc->n_region_names + 1));
	if (!new_names)
		return JNL_MESH_ERR_ALLOC;

	desc->region_names = new_names;

	struct jnl_pmsh2d_desc_name *entry =
	    &desc->region_names[desc->n_region_names++];

	entry->marker = marker;

	if (name) {
		tri_copy_name(entry->name, name);
	} else {
		tri_default_name(entry->name, "region", marker);
	}

	return JNL_MESH_OK;
}

//
// Triangle output -> polymesh desc
//

static struct jnl_polymesh2d_desc *tri_desc_alloc(void)
{
	return calloc(1, sizeof(struct jnl_polymesh2d_desc));
}

static enum jnl_mesh_err
tri_desc_fill_vertices(const triangleio *out, struct jnl_polymesh2d_desc *desc)
{
	if (!out->pointlist || out->numberofpoints <= 0)
		return JNL_MESH_ERR_IMPORT_FAILED;

	desc->n_vertices = out->numberofpoints;
	desc->vx = calloc((size_t)desc->n_vertices, sizeof(f64));
	desc->vy = calloc((size_t)desc->n_vertices, sizeof(f64));

	if (!desc->vx || !desc->vy)
		return JNL_MESH_ERR_ALLOC;

	for (i32 i = 0; i < desc->n_vertices; i++) {
		desc->vx[i] = (f64)out->pointlist[2 * i + 0];
		desc->vy[i] = (f64)out->pointlist[2 * i + 1];
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_desc_fill_cells(const triangleio *out, const struct jnl_tri_mesh_spec *spec,
                    struct jnl_polymesh2d_desc *desc)
{
	if (!out->trianglelist || out->numberoftriangles <= 0)
		return JNL_MESH_ERR_IMPORT_FAILED;

	if (out->numberofcorners < 3)
		return JNL_MESH_ERR_IMPORT_FAILED;

	desc->n_cells = out->numberoftriangles;

	desc->cell_marker = calloc((size_t)desc->n_cells, sizeof(i32));
	desc->cell_vertex_start = calloc((size_t)desc->n_cells + 1, sizeof(i32));
	desc->cell_vertex_list = calloc((size_t)desc->n_cells * 3, sizeof(i32));

	if (!desc->cell_marker || !desc->cell_vertex_start ||
	    !desc->cell_vertex_list)
		return JNL_MESH_ERR_ALLOC;

	for (i32 c = 0; c < desc->n_cells; c++) {
		const int *tri = &out->trianglelist[c * out->numberofcorners];

		i32 marker = 0;
		if (out->triangleattributelist && out->numberoftriangleattributes > 0) {
			marker = (i32)out->triangleattributelist
			             [c * out->numberoftriangleattributes + 0];
		}

		const char *name =
		    tri_marker_map_find_name(&spec->tags.regions, marker);

		if (!name && spec->tags.require_named_regions)
			return JNL_MESH_ERR_UNKNOWN_REGION;

		enum jnl_mesh_err err = desc_add_region_name(desc, marker, name);
		if (err != JNL_MESH_OK)
			return err;

		desc->cell_marker[c] = marker;
		desc->cell_vertex_start[c] = 3 * c;

		desc->cell_vertex_list[3 * c + 0] = tri[0];
		desc->cell_vertex_list[3 * c + 1] = tri[1];
		desc->cell_vertex_list[3 * c + 2] = tri[2];
	}

	desc->cell_vertex_start[desc->n_cells] = 3 * desc->n_cells;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_count_desc_edges(const struct tri_edge_list *edges,
                     const struct jnl_tri_mesh_spec *spec, i32 *out_n_edges)
{
	i32 n = 0;

	if (!edges || !spec || !out_n_edges)
		return JNL_MESH_ERR_INVALID_INPUT;

	for (i32 i = 0; i < edges->len; i++) {
		const struct tri_edge_adj *e = &edges->data[i];

		if (e->marker == 0) {
			if (e->cell1 < 0)
				return JNL_MESH_ERR_UNLABELLED_BOUNDARY;

			continue;
		}

		if (e->cell1 < 0) {
			if (jnl_tri_tags_is_baffle_marker(&spec->tags, e->marker))
				return JNL_MESH_ERR_INVALID_BAFFLE_EDGE;

			if (!tri_marker_map_contains(&spec->tags.patches, e->marker))
				return JNL_MESH_ERR_UNKNOWN_PATCH;

			n++;
			continue;
		}

		if (jnl_tri_tags_is_baffle_marker(&spec->tags, e->marker)) {
			n++;
			continue;
		}

		/*
		 * Two-sided marked edges that are not baffles are treated as
		 * ordinary constrained internal edges. They are not emitted into
		 * the polymesh desc because the polymesh builder only wants
		 * boundary/baffle labels.
		 */
	}

	*out_n_edges = n;
	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_desc_fill_edges(const struct tri_edge_list *edges,
                    const struct jnl_tri_mesh_spec *spec,
                    struct jnl_polymesh2d_desc *desc)
{
	enum jnl_mesh_err err;
	i32 n_desc_edges = 0;

	err = tri_count_desc_edges(edges, spec, &n_desc_edges);
	if (err != JNL_MESH_OK)
		return err;

	desc->n_edges = n_desc_edges;
	desc->edges = calloc((size_t)n_desc_edges, sizeof(*desc->edges));

	if (n_desc_edges > 0 && !desc->edges)
		return JNL_MESH_ERR_ALLOC;

	i32 out = 0;

	for (i32 i = 0; i < edges->len; i++) {
		const struct tri_edge_adj *e = &edges->data[i];

		if (e->marker == 0)
			continue;

		if (e->cell1 < 0) {
			struct jnl_pmsh2d_desc_edge *de = &desc->edges[out++];

			de->v0 = e->a;
			de->v1 = e->b;
			de->kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY;
			de->marker = e->marker;

			continue;
		}

		if (jnl_tri_tags_is_baffle_marker(&spec->tags, e->marker)) {
			struct jnl_pmsh2d_desc_edge *de = &desc->edges[out++];

			de->v0 = e->a;
			de->v1 = e->b;
			de->kind = JNL_PMSH2D_DESC_EDGE_BAFFLE;
			de->marker = e->marker;
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_desc_fill_names(const struct jnl_tri_mesh_spec *spec,
                    struct jnl_polymesh2d_desc *desc)
{
	enum jnl_mesh_err err;

	err = desc_copy_marker_map(&desc->patch_names, &desc->n_patch_names,
	                           &spec->tags.patches);
	if (err != JNL_MESH_OK)
		return err;

	err = desc_copy_marker_map(&desc->baffle_names, &desc->n_baffle_names,
	                           &spec->tags.baffles);
	if (err != JNL_MESH_OK)
		return err;

	/*
	 * Region names are partly built from actual Triangle output attributes,
	 * so unknown/unregistered region markers can be auto-named when
	 * require_named_regions == false.
	 */
	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_output_to_desc(const triangleio *out, const struct jnl_tri_mesh_spec *spec,
                   struct jnl_polymesh2d_desc **out_desc)
{
	enum jnl_mesh_err err;
	struct tri_edge_list edges;
	struct jnl_polymesh2d_desc *desc = NULL;

	tri_edge_list_init(&edges);

	if (!out || !spec || !out_desc)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_desc = NULL;

	desc = tri_desc_alloc();
	if (!desc)
		return JNL_MESH_ERR_ALLOC;

	err = tri_desc_fill_names(spec, desc);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_desc_fill_vertices(out, desc);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_desc_fill_cells(out, spec, desc);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_build_edge_adjacency(out, &edges);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_apply_edge_markers(out, &edges);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_desc_fill_edges(&edges, spec, desc);
	if (err != JNL_MESH_OK)
		goto fail;

	err = jnl_polymesh2d_desc_check(desc);
	if (err != JNL_MESH_OK)
		goto fail;

	*out_desc = desc;
	tri_edge_list_free(&edges);
	return JNL_MESH_OK;

fail:
	tri_edge_list_free(&edges);
	jnl_polymesh2d_desc_free(desc);
	return err;
}

//
// Public API
//

enum jnl_mesh_err
jnl_trimesh2d_desc_from_pslg(const struct jnl_pslg *pslg,
                             const struct jnl_tri_mesh_spec *spec,
                             struct jnl_polymesh2d_desc **out_desc)
{
	enum jnl_mesh_err err = JNL_MESH_OK;

	context *ctx = NULL;
	triangleio in;
	triangleio out;
	char switches[128];

	triangleio_init(&in);
	triangleio_init(&out);

	if (!out_desc)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_desc = NULL;

	err = tri_validate_inputs(pslg, spec);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_build_switches(&spec->opts, switches, sizeof(switches));
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_pslg_to_triangle_input(pslg, &spec->opts, &in);
	if (err != JNL_MESH_OK)
		goto cleanup;

	ctx = triangle_context_create();
	if (!ctx) {
		err = JNL_MESH_ERR_ALLOC;
		goto cleanup;
	}

	if (triangle_context_options(ctx, switches) != 0) {
		err = JNL_MESH_ERR_INVALID_INPUT;
		goto cleanup;
	}

	if (triangle_mesh_create(ctx, &in) != 0) {
		err = JNL_MESH_ERR_IMPORT_FAILED;
		goto cleanup;
	}

	if (triangle_mesh_copy(ctx, &out, 1, 1) != 0) {
		err = JNL_MESH_ERR_IMPORT_FAILED;
		goto cleanup;
	}

	err = tri_output_to_desc(&out, spec, out_desc);

cleanup:
	triangleio_free_input(&in);
	triangleio_free_output(&out);

	if (ctx)
		triangle_context_destroy(ctx);

	if (err != JNL_MESH_OK && out_desc && *out_desc) {
		jnl_polymesh2d_desc_free(*out_desc);
		*out_desc = NULL;
	}

	return err;
}

enum jnl_mesh_err jnl_trimesh2d_from_pslg(const struct jnl_pslg *pslg,
                                          const struct jnl_tri_mesh_spec *spec,
                                          struct jnl_polymesh2d **out_mesh)
{
	enum jnl_mesh_err err;
	struct jnl_polymesh2d_desc *desc = NULL;

	if (!out_mesh)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_mesh = NULL;

	err = jnl_trimesh2d_desc_from_pslg(pslg, spec, &desc);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_polymesh2d_build(desc, out_mesh);

	jnl_polymesh2d_desc_free(desc);
	return err;
}
