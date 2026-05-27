#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

// from vendored Triangle.h
#include "triangle.h"
#include "triangle_api.h"

#include "mesh2d.h"
#include "internal.h"

//
// Option builder
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

//
// Cell sizing helpers for opts
//

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
	if (target_cells <= 0)
		return opts;

	struct jnl_aabb bbox = jnl_pslg_bbox(pslg);
	double w = bbox.max_x - bbox.min_x;
	double h = bbox.max_y - bbox.min_y;
	double bbox_area = w * h;

	// bbox_area overestimates, factor of 0.9 roughly compensates
	double target_area = (bbox_area * 0.9) / (double)target_cells;

	return jnl_tri_opts_set_global_max_area(opts, target_area);
}

struct jnl_tri_opts jnl_tri_opts_set_resolution(struct jnl_tri_opts opts,
                                                const struct jnl_pslg *pslg,
                                                double resolution)
{
	if (resolution <= 0.0)
		return opts;

	struct jnl_aabb bbox = jnl_pslg_bbox(pslg);
	double w = bbox.max_x - bbox.min_x;
	double h = bbox.max_y - bbox.min_y;
	double scale = (w < h ? w : h);

	// Edge length target = resolution * scale.
	// Equilateral triangle area = (sqrt(3)/4) * edge^2 ~ 0.433 * edge^2.
	double edge = resolution * scale;
	double target_area = 0.433 * edge * edge;

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
// Triangle mesh spec / marker metadata
//

static void jnl_tri_copy_name(char dst[JNL_MESH2D_NAME_CAP], const char *src)
{
	if (!src) {
		dst[0] = '\0';
		return;
	}

	strncpy(dst, src, JNL_MESH2D_NAME_CAP - 1);
	dst[JNL_MESH2D_NAME_CAP - 1] = '\0';
}

static const struct jnl_tri_marker_name *
jnl_tri_marker_map_find_entry(const struct jnl_tri_marker_map *map, i32 marker)
{
	if (!map)
		return NULL;

	for (u32 i = 0; i < map->len; i++) {
		if (map->data[i].marker == marker) {
			return &map->data[i];
		}
	}

	return NULL;
}

static enum jnl_mesh_err
jnl_tri_marker_map_reserve(struct jnl_tri_marker_map *map, u32 min_cap)
{
	if (map->cap >= min_cap)
		return JNL_MESH_OK;

	u32 new_cap = map->cap ? map->cap * 2 : 4;
	while (new_cap < min_cap)
		new_cap *= 2;

	struct jnl_tri_marker_name *new_data =
	    realloc(map->data, new_cap * sizeof(*new_data));

	if (!new_data)
		return JNL_MESH_ERR_ALLOC;

	map->data = new_data;
	map->cap = new_cap;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err jnl_tri_marker_map_add(struct jnl_tri_marker_map *map,
                                                i32 marker, const char *name)
{
	if (!map || !name || name[0] == '\0') {
		return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (jnl_tri_marker_map_find_entry(map, marker)) {
		return JNL_MESH_ERR_DUPLICATE_MARKER;
	}

	enum jnl_mesh_err err = jnl_tri_marker_map_reserve(map, map->len + 1);
	if (err != JNL_MESH_OK)
		return err;

	struct jnl_tri_marker_name *entry = &map->data[map->len++];
	entry->marker = marker;
	jnl_tri_copy_name(entry->name, name);

	return JNL_MESH_OK;
}

static void jnl_tri_marker_map_free(struct jnl_tri_marker_map *map)
{
	if (!map)
		return;

	free(map->data);
	map->data = NULL;
	map->len = 0;
	map->cap = 0;
}

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

	jnl_tri_marker_map_free(&tags->patches);
	jnl_tri_marker_map_free(&tags->baffles);
	jnl_tri_marker_map_free(&tags->regions);

	tags->require_named_patches = false;
	tags->require_named_baffles = false;
	tags->require_named_regions = false;
}

enum jnl_mesh_err jnl_tri_tags_add_patch(struct jnl_tri_tags *tags, i32 marker,
                                         const char *name)
{
	if (!tags)
		return JNL_MESH_ERR_INVALID_INPUT;
	return jnl_tri_marker_map_add(&tags->patches, marker, name);
}

enum jnl_mesh_err jnl_tri_tags_add_baffle(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name)
{
	if (!tags)
		return JNL_MESH_ERR_INVALID_INPUT;
	return jnl_tri_marker_map_add(&tags->baffles, marker, name);
}

enum jnl_mesh_err jnl_tri_tags_add_region(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name)
{
	if (!tags)
		return JNL_MESH_ERR_INVALID_INPUT;
	return jnl_tri_marker_map_add(&tags->regions, marker, name);
}

const char *jnl_tri_tags_find_patch(const struct jnl_tri_tags *tags, i32 marker)
{
	if (!tags)
		return NULL;

	const struct jnl_tri_marker_name *entry =
	    jnl_tri_marker_map_find_entry(&tags->patches, marker);

	return entry ? entry->name : NULL;
}

const char *jnl_tri_tags_find_baffle(const struct jnl_tri_tags *tags,
                                     i32 marker)
{
	if (!tags)
		return NULL;

	const struct jnl_tri_marker_name *entry =
	    jnl_tri_marker_map_find_entry(&tags->baffles, marker);

	return entry ? entry->name : NULL;
}

const char *jnl_tri_tags_find_region(const struct jnl_tri_tags *tags,
                                     i32 marker)
{
	if (!tags)
		return NULL;

	const struct jnl_tri_marker_name *entry =
	    jnl_tri_marker_map_find_entry(&tags->regions, marker);

	return entry ? entry->name : NULL;
}

bool jnl_tri_tags_is_baffle_marker(const struct jnl_tri_tags *tags, i32 marker)
{
	return jnl_tri_tags_find_baffle(tags, marker) != NULL;
}

//
// Triangle diagnostic data structure
//

struct tri_diag {
	i32 marker;
	i32 edge_index;
	i32 triangle_index;
	char message[128];
};

//
// Triangle output build data
//

struct tri_face_rec {
	i32 v0, v1;
	i32 owner, neighbour;
	i32 marker;
};

struct tri_cell_rec {
	i32 v[3];
	i32 marker;

	// Original Triangle cell index before region grouping.
	i32 old_index;
};

struct tri_group_rec {
	i32 marker;
	char name[JNL_MESH2D_NAME_CAP];

	// Local start/count inside the corresponding temporary array.
	i32 start;
	i32 count;
};

struct tri_mesh_build {
	i32 n_vertices;
	f64 *vx, *vy;

	i32 n_cells;
	struct tri_cell_rec *cells;

	// old Triangle cell index -> final grouped cell index.
	i32 *cell_old_to_new;

	struct tri_face_rec *internal_faces;
	i32 n_internal_faces, cap_internal_faces;

	struct tri_face_rec *baffle_faces;
	i32 n_baffle_faces, cap_baffle_faces;

	struct tri_face_rec *patch_faces;
	i32 n_patch_faces, cap_patch_faces;

	struct tri_group_rec *baffle_groups;
	i32 n_baffle_groups, cap_baffle_groups;

	struct tri_group_rec *patch_groups;
	i32 n_patch_groups, cap_patch_groups;

	struct tri_group_rec *region_groups;
	i32 n_region_groups, cap_region_groups;
};

//
// Triangle Edge Adjacency
//

struct tri_edge_adj {
	// Sorted key
	i32 a, b;

	// Final oriented face vertices
	i32 v0, v1;

	i32 cell0, cell1;
	i32 local0, local1;

	i32 marker;
	bool is_segment;
};

struct tri_edge_list {
	struct tri_edge_adj *data;
	i32 len, cap;
};

//
// Diagnostics
//

static void tri_diag_clear(struct tri_diag *diag)
{
	if (!diag)
		return;

	diag->marker = 0;
	diag->edge_index = -1;
	diag->triangle_index = -1;
	diag->message[0] = '\0';
}

static void tri_diag_set(struct tri_diag *diag, i32 marker, i32 edge_index,
                         i32 triangle_index, const char *message)
{
	if (!diag)
		return;

	diag->marker = marker;
	diag->edge_index = edge_index;
	diag->triangle_index = triangle_index;

	if (!message) {
		diag->message[0] = '\0';
		return;
	}

	strncpy(diag->message, message, sizeof(diag->message) - 1);
	diag->message[sizeof(diag->message) - 1] = '\0';
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
// Triangle Input
//

static enum jnl_mesh_err
tri_validate_inputs(const struct jnl_pslg *pslg,
                    const struct jnl_tri_mesh_spec *spec, struct tri_diag *diag)
{
	if (!pslg || !spec) {
		tri_diag_set(diag, 0, -1, -1, "NULL PSLG or Triangle spec");
		return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (pslg->nodes.len < 3) {
		tri_diag_set(diag, 0, -1, -1, "PSLG must contain at least three nodes");
		return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (spec->opts.min_angle_deg < 0.0) {
		tri_diag_set(diag, 0, -1, -1, "Minimum angle cannot be negative");
		return JNL_MESH_ERR_INVALID_INPUT;
	}

	if (spec->opts.global_max_area < 0.0) {
		tri_diag_set(diag, 0, -1, -1, "Global maximum area cannot be negative");
		return JNL_MESH_ERR_INVALID_INPUT;
	}

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

	// p: PSLG input.
	// A: propagate region attributes into triangle attributes.
	if (tri_append_switch(buf, buf_len, &pos, "pA") != JNL_MESH_OK) {
		return JNL_MESH_ERR_INVALID_INPUT;
	}

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
		// Let Triangle use regionlist area constraints.
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

	if (!in->pointlist || !in->pointmarkerlist) {
		return JNL_MESH_ERR_ALLOC;
	}

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

	if (!in->segmentlist || !in->segmentmarkerlist) {
		return JNL_MESH_ERR_ALLOC;
	}

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
                           const struct jnl_tri_opts *opts, triangleio *in,
                           struct tri_diag *diag)
{
	enum jnl_mesh_err err;

	(void)diag;

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
// Triangle Output Build Data Lifecycle
//

static void tri_mesh_build_init(struct tri_mesh_build *build)
{
	if (!build)
		return;
	memset(build, 0, sizeof(*build));
}

static void tri_mesh_build_free(struct tri_mesh_build *build)
{
	if (!build)
		return;

	free(build->vx);
	free(build->vy);
	free(build->cells);
	free(build->cell_old_to_new);

	free(build->internal_faces);
	free(build->baffle_faces);
	free(build->patch_faces);

	free(build->baffle_groups);
	free(build->patch_groups);
	free(build->region_groups);

	tri_mesh_build_init(build);
}

//
// Edge Adjacency Helpers
//

static void tri_edge_list_init(struct tri_edge_list *edges)
{
	if (!edges)
		return;
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
	    realloc(edges->data, sizeof(*new_data) * new_cap);

	if (!new_data)
		return JNL_MESH_ERR_ALLOC;

	edges->data = new_data;
	edges->cap = new_cap;

	return JNL_MESH_OK;
}

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

static i32 tri_edge_list_find(const struct tri_edge_list *edges, i32 a, i32 b)
{
	for (i32 i = 0; i < edges->len; i++) {
		if (edges->data[i].a == a && edges->data[i].b == b) {
			return i;
		}
	}

	return -1;
}

static enum jnl_mesh_err
tri_edge_list_add_or_update(struct tri_edge_list *edges, i32 v0, i32 v1,
                            i32 cell, i32 local_edge, struct tri_diag *diag)
{
	i32 a, b;
	tri_edge_key(v0, v1, &a, &b);

	i32 found = tri_edge_list_find(edges, a, b);

	if (found >= 0) {
		struct tri_edge_adj *edge = &edges->data[found];

		if (edge->cell1 >= 0) {
			tri_diag_set(diag, edge->marker, found, cell,
			             "Non-manifold edge: more than two adjacent triangles");
			return JNL_MESH_ERR_INVALID_INPUT;
		}

		edge->cell1 = cell;
		edge->local1 = local_edge;
		return JNL_MESH_OK;
	}

	enum jnl_mesh_err err = tri_edge_list_reserve(edges, edges->len + 1);
	if (err != JNL_MESH_OK)
		return err;

	struct tri_edge_adj *edge = &edges->data[edges->len++];

	edge->a = a;
	edge->b = b;

	// Triangle emits triangle vertices CCW. For a CCW cell edge v0->v1,
	// the cell exterior is to the right. Your geometry convention appears
	// to use the left normal of face_vertex order, so store reversed order.
	edge->v0 = v1;
	edge->v1 = v0;

	edge->cell0 = cell;
	edge->cell1 = -1;
	edge->local0 = local_edge;
	edge->local1 = -1;
	edge->marker = 0;
	edge->is_segment = false;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_edge_adjacency_build(const triangleio *out,
                                                  struct tri_edge_list *edges,
                                                  struct tri_diag *diag)
{
	if (!out || !edges || !out->trianglelist) {
		return JNL_MESH_ERR_INVALID_INPUT;
	}

	for (i32 c = 0; c < out->numberoftriangles; c++) {
		i32 *tri = &out->trianglelist[c * out->numberofcorners];

		i32 v0 = tri[0];
		i32 v1 = tri[1];
		i32 v2 = tri[2];

		enum jnl_mesh_err err;

		err = tri_edge_list_add_or_update(edges, v0, v1, c, 0, diag);
		if (err != JNL_MESH_OK)
			return err;

		err = tri_edge_list_add_or_update(edges, v1, v2, c, 1, diag);
		if (err != JNL_MESH_OK)
			return err;

		err = tri_edge_list_add_or_update(edges, v2, v0, c, 2, diag);
		if (err != JNL_MESH_OK)
			return err;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_edge_adjacency_apply_edge_markers(
    const triangleio *out, struct tri_edge_list *edges, struct tri_diag *diag)
{
	if (!out || !edges)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!out->edgelist || !out->edgemarkerlist || out->numberofedges <= 0) {
		tri_diag_set(diag, 0, -1, -1,
		             "Triangle output contains no edge markers");
		return JNL_MESH_ERR_TRIANGLE_FAILED;
	}

	for (i32 e = 0; e < out->numberofedges; e++) {
		i32 v0 = out->edgelist[2 * e + 0];
		i32 v1 = out->edgelist[2 * e + 1];

		i32 a, b;
		tri_edge_key(v0, v1, &a, &b);

		i32 found = tri_edge_list_find(edges, a, b);
		if (found < 0) {
			tri_diag_set(
			    diag, 0, e, -1,
			    "Triangle edge output not found in triangle adjacency");
			return JNL_MESH_ERR_TRIANGLE_FAILED;
		}

		edges->data[found].marker = (i32)out->edgemarkerlist[e];
		edges->data[found].is_segment = edges->data[found].marker != 0;
	}

	return JNL_MESH_OK;
}

//
// Build Helpers
//

static enum jnl_mesh_err tri_face_array_reserve(struct tri_face_rec **faces,
                                                i32 *cap, i32 min_cap)
{
	if (*cap >= min_cap)
		return JNL_MESH_OK;

	i32 new_cap = *cap ? *cap * 2 : 64;
	while (new_cap < min_cap)
		new_cap *= 2;

	struct tri_face_rec *new_data =
	    realloc(*faces, sizeof(*new_data) * new_cap);

	if (!new_data)
		return JNL_MESH_ERR_ALLOC;

	*faces = new_data;
	*cap = new_cap;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_group_array_reserve(struct tri_group_rec **groups,
                                                 i32 *cap, i32 min_cap)
{
	if (*cap >= min_cap)
		return JNL_MESH_OK;

	i32 new_cap = *cap ? *cap * 2 : 8;
	while (new_cap < min_cap)
		new_cap *= 2;

	struct tri_group_rec *new_data =
	    realloc(*groups, sizeof(*new_data) * new_cap);

	if (!new_data)
		return JNL_MESH_ERR_ALLOC;

	*groups = new_data;
	*cap = new_cap;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_add_face_rec(struct tri_face_rec **faces, i32 *len,
                                          i32 *cap,
                                          const struct tri_face_rec *face)
{
	enum jnl_mesh_err err = tri_face_array_reserve(faces, cap, *len + 1);
	if (err != JNL_MESH_OK)
		return err;

	(*faces)[(*len)++] = *face;
	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_add_internal_face(struct tri_mesh_build *build,
                                               const struct tri_edge_adj *edge)
{
	struct tri_face_rec face = {
	    .v0 = edge->v0,
	    .v1 = edge->v1,
	    .owner = edge->cell0,
	    .neighbour = edge->cell1,
	    .marker = edge->marker,
	};

	return tri_add_face_rec(&build->internal_faces, &build->n_internal_faces,
	                        &build->cap_internal_faces, &face);
}

static enum jnl_mesh_err
tri_add_baffle_face(struct tri_mesh_build *build,
                    const struct jnl_tri_mesh_spec *spec,
                    const struct tri_edge_adj *edge, struct tri_diag *diag)
{
	{
		const char *name = jnl_tri_tags_find_baffle(&spec->tags, edge->marker);

		if (!name && spec->tags.require_named_baffles) {
			tri_diag_set(diag, edge->marker, -1, edge->cell0,
			             "Baffle marker has no registered baffle");
			return JNL_MESH_ERR_UNKNOWN_BAFFLE;
		}

		struct tri_face_rec face = {
		    .v0 = edge->v0,
		    .v1 = edge->v1,
		    .owner = edge->cell0,
		    .neighbour = edge->cell1,
		    .marker = edge->marker,
		};

		return tri_add_face_rec(&build->baffle_faces, &build->n_baffle_faces,
		                        &build->cap_baffle_faces, &face);
	}
}

static enum jnl_mesh_err
tri_add_patch_face(struct tri_mesh_build *build,
                   const struct jnl_tri_mesh_spec *spec,
                   const struct tri_edge_adj *edge, struct tri_diag *diag)
{
	{
		const char *name = jnl_tri_tags_find_patch(&spec->tags, edge->marker);

		if (!name && spec->tags.require_named_patches) {
			tri_diag_set(diag, edge->marker, -1, edge->cell0,
			             "Patch marker has no registered patch");
			return JNL_MESH_ERR_UNKNOWN_PATCH;
		}

		struct tri_face_rec face = {
		    .v0 = edge->v0,
		    .v1 = edge->v1,
		    .owner = edge->cell0,
		    .neighbour = ~edge->marker,
		    .marker = edge->marker,
		};

		return tri_add_face_rec(&build->patch_faces, &build->n_patch_faces,
		                        &build->cap_patch_faces, &face);
	}
}

//
// Grouping / sorting helpers
//

static int tri_face_rec_marker_cmp(const void *a, const void *b)
{
	const struct tri_face_rec *fa = a;
	const struct tri_face_rec *fb = b;

	if (fa->marker < fb->marker)
		return -1;
	if (fa->marker > fb->marker)
		return 1;
	return 0;
}

static int tri_cell_rec_marker_cmp(const void *a, const void *b)
{
	const struct tri_cell_rec *ca = a;
	const struct tri_cell_rec *cb = b;

	if (ca->marker < cb->marker)
		return -1;
	if (ca->marker > cb->marker)
		return 1;
	return 0;
}

static const char *
tri_marker_map_find_name(const struct jnl_tri_marker_map *map, i32 marker)
{
	const struct jnl_tri_marker_name *entry =
	    jnl_tri_marker_map_find_entry(map, marker);

	return entry ? entry->name : NULL;
}

static const struct jnl_tri_marker_name *
tri_marker_map_find_first_name_entry(const struct jnl_tri_marker_map *map,
                                     const char *name)
{
	if (!map || !name)
		return NULL;

	for (u32 i = 0; i < map->len; i++) {
		if (strcmp(map->data[i].name, name) == 0) {
			return &map->data[i];
		}
	}

	return NULL;
}

static i32
tri_marker_map_canonical_marker_for_name(const struct jnl_tri_marker_map *map,
                                         i32 marker)
{
	const struct jnl_tri_marker_name *entry =
	    jnl_tri_marker_map_find_entry(map, marker);

	if (!entry)
		return marker;

	const struct jnl_tri_marker_name *first =
	    tri_marker_map_find_first_name_entry(map, entry->name);

	return first ? first->marker : marker;
}

static void tri_default_group_name(char dst[JNL_MESH2D_NAME_CAP],
                                   const char *prefix, i32 marker)
{
	snprintf(dst, JNL_MESH2D_NAME_CAP, "%s_%d", prefix, marker);
	dst[JNL_MESH2D_NAME_CAP - 1] = '\0';
}

static void
tri_canonicalize_face_markers_by_name(struct tri_face_rec *faces, i32 n_faces,
                                      const struct jnl_tri_marker_map *map,
                                      bool rewrite_encoded_patch_marker)
{
	for (i32 i = 0; i < n_faces; i++) {
		i32 canonical_marker =
		    tri_marker_map_canonical_marker_for_name(map, faces[i].marker);

		if (canonical_marker == faces[i].marker)
			continue;

		faces[i].marker = canonical_marker;

		/*
		 * Patch faces encode their logical patch marker as neighbour = ~marker.
		 * If we only merge the patch table but leave this value untouched,
		 * downstream code can still observe the old split markers.  Rewrite it
		 * here so same-named patches are fully merged, including face markers.
		 */
		if (rewrite_encoded_patch_marker && faces[i].neighbour < 0) {
			faces[i].neighbour = ~canonical_marker;
		}
	}
}

static void
tri_canonicalize_cell_markers_by_name(struct tri_cell_rec *cells, i32 n_cells,
                                      const struct jnl_tri_marker_map *map)
{
	for (i32 i = 0; i < n_cells; i++) {
		cells[i].marker =
		    tri_marker_map_canonical_marker_for_name(map, cells[i].marker);
	}
}

static enum jnl_mesh_err tri_rebuild_face_groups_from_sorted_faces(
    const struct tri_face_rec *faces, i32 n_faces,
    const struct jnl_tri_marker_map *map, bool require_named,
    enum jnl_mesh_err unknown_err, const char *default_prefix,
    struct tri_group_rec **groups, i32 *n_groups, i32 *cap_groups,
    struct tri_diag *diag)
{
	*n_groups = 0;

	i32 i = 0;
	while (i < n_faces) {
		i32 marker = faces[i].marker;
		i32 start = i;

		while (i < n_faces && faces[i].marker == marker) {
			i++;
		}

		const char *name = tri_marker_map_find_name(map, marker);

		if (!name && require_named) {
			tri_diag_set(diag, marker, start, -1,
			             "Marker has no registered group name");
			return unknown_err;
		}

		enum jnl_mesh_err err =
		    tri_group_array_reserve(groups, cap_groups, *n_groups + 1);

		if (err != JNL_MESH_OK)
			return err;

		struct tri_group_rec *group = &(*groups)[(*n_groups)++];
		group->marker = marker;
		group->start = start;
		group->count = i - start;

		if (name) {
			jnl_tri_copy_name(group->name, name);
		} else {
			tri_default_group_name(group->name, default_prefix, marker);
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_rebuild_region_groups_from_sorted_cells(
    const struct tri_cell_rec *cells, i32 n_cells,
    const struct jnl_tri_marker_map *map, bool require_named,
    struct tri_group_rec **groups, i32 *n_groups, i32 *cap_groups,
    struct tri_diag *diag)
{
	*n_groups = 0;

	i32 i = 0;
	while (i < n_cells) {
		i32 marker = cells[i].marker;
		i32 start = i;

		while (i < n_cells && cells[i].marker == marker) {
			i++;
		}

		const char *name = tri_marker_map_find_name(map, marker);

		if (!name && require_named) {
			tri_diag_set(diag, marker, -1, start,
			             "Region marker has no registered region");
			return JNL_MESH_ERR_UNKNOWN_REGION;
		}

		enum jnl_mesh_err err =
		    tri_group_array_reserve(groups, cap_groups, *n_groups + 1);

		if (err != JNL_MESH_OK)
			return err;

		struct tri_group_rec *group = &(*groups)[(*n_groups)++];
		group->marker = marker;
		group->start = start;
		group->count = i - start;

		if (name) {
			jnl_tri_copy_name(group->name, name);
		} else {
			tri_default_group_name(group->name, "region", marker);
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
tri_group_baffle_faces(struct tri_mesh_build *build,
                       const struct jnl_tri_mesh_spec *spec,
                       struct tri_diag *diag)
{
	{
		if (build->n_baffle_faces == 0)
			return JNL_MESH_OK;

		tri_canonicalize_face_markers_by_name(build->baffle_faces,
		                                      build->n_baffle_faces,
		                                      &spec->tags.baffles, false);

		qsort(build->baffle_faces, build->n_baffle_faces,
		      sizeof(struct tri_face_rec), tri_face_rec_marker_cmp);

		return tri_rebuild_face_groups_from_sorted_faces(
		    build->baffle_faces, build->n_baffle_faces, &spec->tags.baffles,
		    spec->tags.require_named_baffles, JNL_MESH_ERR_UNKNOWN_BAFFLE,
		    "baffle", &build->baffle_groups, &build->n_baffle_groups,
		    &build->cap_baffle_groups, diag);
	}
}

static enum jnl_mesh_err
tri_group_patch_faces(struct tri_mesh_build *build,
                      const struct jnl_tri_mesh_spec *spec,
                      struct tri_diag *diag)
{
	{
		if (build->n_patch_faces == 0)
			return JNL_MESH_OK;

		tri_canonicalize_face_markers_by_name(build->patch_faces,
		                                      build->n_patch_faces,
		                                      &spec->tags.patches, true);

		qsort(build->patch_faces, build->n_patch_faces,
		      sizeof(struct tri_face_rec), tri_face_rec_marker_cmp);

		return tri_rebuild_face_groups_from_sorted_faces(
		    build->patch_faces, build->n_patch_faces, &spec->tags.patches,
		    spec->tags.require_named_patches, JNL_MESH_ERR_UNKNOWN_PATCH,
		    "patch", &build->patch_groups, &build->n_patch_groups,
		    &build->cap_patch_groups, diag);
	}
}

static enum jnl_mesh_err
tri_group_region_cells(struct tri_mesh_build *build,
                       const struct jnl_tri_mesh_spec *spec,
                       struct tri_diag *diag)
{
	{
		if (build->n_cells == 0)
			return JNL_MESH_ERR_TRIANGLE_FAILED;

		tri_canonicalize_cell_markers_by_name(build->cells, build->n_cells,
		                                      &spec->tags.regions);

		qsort(build->cells, build->n_cells, sizeof(struct tri_cell_rec),
		      tri_cell_rec_marker_cmp);

		build->cell_old_to_new = malloc(sizeof(i32) * build->n_cells);
		if (!build->cell_old_to_new)
			return JNL_MESH_ERR_ALLOC;

		for (i32 new_i = 0; new_i < build->n_cells; new_i++) {
			i32 old_i = build->cells[new_i].old_index;
			build->cell_old_to_new[old_i] = new_i;
		}

		return tri_rebuild_region_groups_from_sorted_cells(
		    build->cells, build->n_cells, &spec->tags.regions,
		    spec->tags.require_named_regions, &build->region_groups,
		    &build->n_region_groups, &build->cap_region_groups, diag);
	}
}

//
// Edge classification
//

// forward declaration
static enum jnl_mesh_err tri_classify_edge(const struct tri_edge_adj *edge,
                                           const struct jnl_tri_mesh_spec *spec,
                                           struct tri_mesh_build *build,
                                           struct tri_diag *diag);

static enum jnl_mesh_err
tri_classify_edges(const struct tri_edge_list *edges,
                   const struct jnl_tri_mesh_spec *spec,
                   struct tri_mesh_build *build, struct tri_diag *diag)
{
	for (i32 i = 0; i < edges->len; i++) {
		enum jnl_mesh_err err =
		    tri_classify_edge(&edges->data[i], spec, build, diag);

		if (err != JNL_MESH_OK)
			return err;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_classify_edge(const struct tri_edge_adj *edge,
                                           const struct jnl_tri_mesh_spec *spec,
                                           struct tri_mesh_build *build,
                                           struct tri_diag *diag)
{
	if (edge->cell1 >= 0) {
		if (jnl_tri_tags_is_baffle_marker(&spec->tags, edge->marker)) {
			return tri_add_baffle_face(build, spec, edge, diag);
		}

		return tri_add_internal_face(build, edge);
	}

	if (jnl_tri_tags_is_baffle_marker(&spec->tags, edge->marker)) {
		tri_diag_set(diag, edge->marker, -1, edge->cell0,
		             "Baffle marker used on exterior boundary edge");
		return JNL_MESH_ERR_INVALID_BAFFLE;
	}

	if (!jnl_tri_tags_find_patch(&spec->tags, edge->marker)) {
		tri_diag_set(diag, edge->marker, -1, edge->cell0,
		             "Boundary edge marker has no registered patch");
		return JNL_MESH_ERR_UNKNOWN_PATCH;
	}

	return tri_add_patch_face(build, spec, edge, diag);
}

//
// Triangle Output -> Build
//

static enum jnl_mesh_err tri_extract_vertices(const triangleio *out,
                                              struct tri_mesh_build *build,
                                              struct tri_diag *diag)
{
	(void)diag;

	if (!out->pointlist || out->numberofpoints <= 0) {
		return JNL_MESH_ERR_TRIANGLE_FAILED;
	}

	build->n_vertices = out->numberofpoints;
	build->vx = malloc(sizeof(f64) * build->n_vertices);
	build->vy = malloc(sizeof(f64) * build->n_vertices);

	if (!build->vx || !build->vy)
		return JNL_MESH_ERR_ALLOC;

	for (i32 i = 0; i < build->n_vertices; i++) {
		build->vx[i] = (f64)out->pointlist[2 * i + 0];
		build->vy[i] = (f64)out->pointlist[2 * i + 1];
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_extract_cells(const triangleio *out,
                                           const struct jnl_tri_mesh_spec *spec,
                                           struct tri_mesh_build *build,
                                           struct tri_diag *diag)
{
	(void)spec;

	if (!out->trianglelist || out->numberoftriangles <= 0) {
		tri_diag_set(diag, 0, -1, -1, "Triangle produced no triangles");
		return JNL_MESH_ERR_TRIANGLE_FAILED;
	}

	if (out->numberofcorners < 3) {
		tri_diag_set(diag, 0, -1, -1,
		             "Triangle output has fewer than 3 corners");
		return JNL_MESH_ERR_TRIANGLE_FAILED;
	}

	build->n_cells = out->numberoftriangles;
	build->cells = malloc(sizeof(struct tri_cell_rec) * build->n_cells);

	if (!build->cells)
		return JNL_MESH_ERR_ALLOC;

	for (i32 c = 0; c < build->n_cells; c++) {
		struct tri_cell_rec *cell = &build->cells[c];

		cell->v[0] = out->trianglelist[c * out->numberofcorners + 0];
		cell->v[1] = out->trianglelist[c * out->numberofcorners + 1];
		cell->v[2] = out->trianglelist[c * out->numberofcorners + 2];
		cell->old_index = c;

		if (out->triangleattributelist && out->numberoftriangleattributes > 0) {
			cell->marker = (i32)out->triangleattributelist
			                   [c * out->numberoftriangleattributes + 0];
		} else {
			cell->marker = 0;
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_extract_faces(const triangleio *out,
                                           const struct jnl_tri_mesh_spec *spec,
                                           struct tri_mesh_build *build,
                                           struct tri_diag *diag)
{
	enum jnl_mesh_err err;
	struct tri_edge_list edges;

	tri_edge_list_init(&edges);

	err = tri_edge_adjacency_build(out, &edges, diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_edge_adjacency_apply_edge_markers(out, &edges, diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_classify_edges(&edges, spec, build, diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_group_baffle_faces(build, spec, diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_group_patch_faces(build, spec, diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

cleanup:
	tri_edge_list_free(&edges);
	return err;
}

static enum jnl_mesh_err
tri_output_to_build(const triangleio *out, const struct jnl_tri_mesh_spec *spec,
                    struct tri_mesh_build *build, struct tri_diag *diag)
{
	enum jnl_mesh_err err;

	if (!out || !spec || !build)
		return JNL_MESH_ERR_INVALID_INPUT;

	err = tri_extract_vertices(out, build, diag);
	if (err != JNL_MESH_OK)
		return err;

	err = tri_extract_cells(out, spec, build, diag);
	if (err != JNL_MESH_OK)
		return err;

	err = tri_extract_faces(out, spec, build, diag);
	if (err != JNL_MESH_OK)
		return err;

	err = tri_group_region_cells(build, spec, diag);
	if (err != JNL_MESH_OK)
		return err;

	return JNL_MESH_OK;
}

//
// Commit detail helpers
//

static void tri_commit_vertices(jnl_arena *arena,
                                const struct tri_mesh_build *build,
                                struct jnl_mesh_topo *topo)
{
	(void)arena;

	for (i32 i = 0; i < build->n_vertices; i++) {
		topo->vx[i] = build->vx[i];
		topo->vy[i] = build->vy[i];
	}
}

static i32 tri_remap_cell(const struct tri_mesh_build *build, i32 old_cell)
{
	if (old_cell < 0)
		return old_cell;
	return build->cell_old_to_new[old_cell];
}

static void tri_write_face_block(struct jnl_mesh_topo *topo,
                                 const struct tri_mesh_build *build,
                                 i32 dst_start,
                                 const struct tri_face_rec *faces, i32 n_faces)
{
	for (i32 i = 0; i < n_faces; i++) {
		i32 f = dst_start + i;

		topo->face_vertex[2 * f + 0] = faces[i].v0;
		topo->face_vertex[2 * f + 1] = faces[i].v1;

		topo->owner[f] = tri_remap_cell(build, faces[i].owner);

		if (faces[i].neighbour >= 0) {
			topo->neighbour[f] = tri_remap_cell(build, faces[i].neighbour);
		} else {
			topo->neighbour[f] = faces[i].neighbour;
		}
	}
}

static void tri_commit_faces(jnl_arena *arena,
                             const struct tri_mesh_build *build,
                             struct jnl_mesh_topo *topo)
{
	(void)arena;

	i32 f = 0;

	tri_write_face_block(topo, build, f, build->internal_faces,
	                     build->n_internal_faces);

	f += build->n_internal_faces;

	tri_write_face_block(topo, build, f, build->baffle_faces,
	                     build->n_baffle_faces);

	f += build->n_baffle_faces;

	tri_write_face_block(topo, build, f, build->patch_faces,
	                     build->n_patch_faces);
}

static void tri_write_cell_block(struct jnl_mesh_topo *topo, i32 dst_start,
                                 const struct tri_cell_rec *cells, i32 n_cells)
{
	for (i32 i = 0; i < n_cells; i++) {
		i32 c = dst_start + i;

		topo->cell_marker[c] = cells[i].marker;
		topo->cell_vertex_start[c] = c * 3;

		topo->cell_vertex_list[c * 3 + 0] = cells[i].v[0];
		topo->cell_vertex_list[c * 3 + 1] = cells[i].v[1];
		topo->cell_vertex_list[c * 3 + 2] = cells[i].v[2];
	}

	topo->cell_vertex_start[dst_start + n_cells] = (dst_start + n_cells) * 3;
}

static void tri_commit_cells(jnl_arena *arena,
                             const struct tri_mesh_build *build,
                             struct jnl_mesh_topo *topo)
{
	(void)arena;
	tri_write_cell_block(topo, 0, build->cells, build->n_cells);
}

//
// Commit
//

static u64 tri_mesh_arena_size(const struct tri_mesh_build *build)
{
	i32 n_faces =
	    build->n_internal_faces + build->n_baffle_faces + build->n_patch_faces;

	i32 n_cells = build->n_cells;
	i32 n_vertices = build->n_vertices;

	u64 size = 0;

	size += ARENA_SIZE(struct jnl_mesh, 1);

	size += ARENA_SIZE(f64, n_vertices); // vx
	size += ARENA_SIZE(f64, n_vertices); // vy

	size += ARENA_SIZE(i32, n_faces * 2); // face_vertex
	size += ARENA_SIZE(i32, n_faces);     // owner
	size += ARENA_SIZE(i32, n_faces);     // neighbour

	size += ARENA_SIZE(i32, n_cells);     // cell_marker
	size += ARENA_SIZE(i32, n_cells + 1); // cell_vertex_start
	size += ARENA_SIZE(i32, n_cells * 3); // cell_vertex_list

	size += ARENA_SIZE(struct jnl_patch, build->n_patch_groups);
	size += ARENA_SIZE(struct jnl_baffle, build->n_baffle_groups);
	size += ARENA_SIZE(struct jnl_region, build->n_region_groups);

	// Geometry.
	size += ARENA_SIZE(f64, n_faces); // face_cx
	size += ARENA_SIZE(f64, n_faces); // face_cy
	size += ARENA_SIZE(f64, n_faces); // face_nx
	size += ARENA_SIZE(f64, n_faces); // face_ny
	size += ARENA_SIZE(f64, n_faces); // face_area

	size += ARENA_SIZE(f64, n_cells); // cell_cx
	size += ARENA_SIZE(f64, n_cells); // cell_cy
	size += ARENA_SIZE(f64, n_cells); // cell_vol

	// Interpolation.
	size += ARENA_SIZE(f64, n_faces); // weight
	size += ARENA_SIZE(f64, n_faces); // delta_coeff
	size += ARENA_SIZE(f64, n_faces); // corr_x
	size += ARENA_SIZE(f64, n_faces); // corr_y
	size += ARENA_SIZE(f64, n_faces); // skew_x
	size += ARENA_SIZE(f64, n_faces); // skew_y

	return size + size / 2;
}

static enum jnl_mesh_err tri_commit_topology(jnl_arena *arena,
                                             const struct tri_mesh_build *build,
                                             struct jnl_mesh_topo *topo)
{
	i32 n_faces =
	    build->n_internal_faces + build->n_baffle_faces + build->n_patch_faces;

	topo->n_vertices = build->n_vertices;
	topo->n_faces = n_faces;
	topo->n_internal_faces = build->n_internal_faces;
	topo->n_cells = build->n_cells;

	topo->vx = ARENA_PUSH_ARRAY_Z(arena, f64, topo->n_vertices);
	topo->vy = ARENA_PUSH_ARRAY_Z(arena, f64, topo->n_vertices);

	topo->face_vertex = ARENA_PUSH_ARRAY_Z(arena, i32, topo->n_faces * 2);
	topo->owner = ARENA_PUSH_ARRAY_Z(arena, i32, topo->n_faces);
	topo->neighbour = ARENA_PUSH_ARRAY_Z(arena, i32, topo->n_faces);

	topo->cell_marker = ARENA_PUSH_ARRAY_Z(arena, i32, topo->n_cells);
	topo->cell_vertex_start = ARENA_PUSH_ARRAY_Z(arena, i32, topo->n_cells + 1);
	topo->cell_vertex_list = ARENA_PUSH_ARRAY_Z(arena, i32, topo->n_cells * 3);

	if (!topo->vx || !topo->vy || !topo->face_vertex || !topo->owner ||
	    !topo->neighbour || !topo->cell_marker || !topo->cell_vertex_start ||
	    !topo->cell_vertex_list) {
		return JNL_MESH_ERR_ALLOC;
	}

	tri_commit_vertices(arena, build, topo);
	tri_commit_faces(arena, build, topo);
	tri_commit_cells(arena, build, topo);

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_commit_patches(jnl_arena *arena,
                                            const struct tri_mesh_build *build,
                                            struct jnl_patches *patches)
{
	patches->n_patches = build->n_patch_groups;

	if (patches->n_patches == 0) {
		patches->data = NULL;
		return JNL_MESH_OK;
	}

	patches->data =
	    ARENA_PUSH_ARRAY_Z(arena, struct jnl_patch, patches->n_patches);

	if (!patches->data)
		return JNL_MESH_ERR_ALLOC;

	i32 patch_base = build->n_internal_faces + build->n_baffle_faces;

	for (i32 i = 0; i < patches->n_patches; i++) {
		const struct tri_group_rec *group = &build->patch_groups[i];
		struct jnl_patch *patch = &patches->data[i];

		jnl_tri_copy_name(patch->name, group->name);
		patch->marker = group->marker;
		patch->start_face = patch_base + group->start;
		patch->n_faces = group->count;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_commit_baffles(jnl_arena *arena,
                                            const struct tri_mesh_build *build,
                                            struct jnl_baffles *baffles)
{
	baffles->n_baffles = build->n_baffle_groups;
	baffles->n_baffle_faces = build->n_baffle_faces;

	if (baffles->n_baffles == 0) {
		baffles->data = NULL;
		return JNL_MESH_OK;
	}

	baffles->data =
	    ARENA_PUSH_ARRAY_Z(arena, struct jnl_baffle, baffles->n_baffles);

	if (!baffles->data)
		return JNL_MESH_ERR_ALLOC;

	i32 baffle_base = build->n_internal_faces;

	for (i32 i = 0; i < baffles->n_baffles; i++) {
		const struct tri_group_rec *group = &build->baffle_groups[i];
		struct jnl_baffle *baffle = &baffles->data[i];

		jnl_tri_copy_name(baffle->name, group->name);
		baffle->marker = group->marker;
		baffle->start_face = baffle_base + group->start;
		baffle->n_faces = group->count;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_commit_regions(jnl_arena *arena,
                                            const struct tri_mesh_build *build,
                                            struct jnl_regions *regions)
{
	regions->n_regions = build->n_region_groups;

	if (regions->n_regions == 0) {
		regions->data = NULL;
		return JNL_MESH_OK;
	}

	regions->data =
	    ARENA_PUSH_ARRAY_Z(arena, struct jnl_region, regions->n_regions);

	if (!regions->data)
		return JNL_MESH_ERR_ALLOC;

	for (i32 i = 0; i < regions->n_regions; i++) {
		const struct tri_group_rec *group = &build->region_groups[i];
		struct jnl_region *region = &regions->data[i];

		jnl_tri_copy_name(region->name, group->name);
		region->marker = group->marker;
		region->start_cell = group->start;
		region->n_cells = group->count;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_commit_geometry_and_interp(jnl_arena *arena,
                                                        struct jnl_mesh *mesh)
{
	mesh->geom = jnl_mesh2d_geom_gen(arena, mesh->topo);
	mesh->interp = jnl_mesh2d_interp_gen(arena, mesh->topo, mesh->geom);

	return JNL_MESH_OK;
}

static enum jnl_mesh_err tri_commit_mesh(const struct tri_mesh_build *build,
                                         const struct jnl_tri_mesh_spec *spec,
                                         struct jnl_mesh **out_mesh)
{
	(void)spec;

	if (!build || !out_mesh)
		return JNL_MESH_ERR_INVALID_INPUT;

	u64 arena_size = tri_mesh_arena_size(build);
	jnl_arena *arena = arena_create(arena_size);

	if (!arena)
		return JNL_MESH_ERR_ALLOC;

	struct jnl_mesh *mesh = ARENA_PUSH_STRUCT_Z(arena, struct jnl_mesh);
	if (!mesh) {
		arena_destroy(arena);
		return JNL_MESH_ERR_ALLOC;
	}

	mesh->arena = arena;

	enum jnl_mesh_err err;

	err = tri_commit_topology(arena, build, &mesh->topo);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_commit_patches(arena, build, &mesh->patches);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_commit_baffles(arena, build, &mesh->baffles);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_commit_regions(arena, build, &mesh->regions);
	if (err != JNL_MESH_OK)
		goto fail;

	err = tri_commit_geometry_and_interp(arena, mesh);
	if (err != JNL_MESH_OK)
		goto fail;

	*out_mesh = mesh;
	return JNL_MESH_OK;

fail:
	arena_destroy(arena);
	*out_mesh = NULL;
	return err;
}

//
// PUBLIC API
//

enum jnl_mesh_err jnl_mesh2d_from_pslg_tri(const struct jnl_pslg *pslg,
                                           const struct jnl_tri_mesh_spec *spec,
                                           struct jnl_mesh **out_mesh)
{
	enum jnl_mesh_err err = JNL_MESH_OK;

	context *ctx = NULL;
	triangleio in;
	triangleio out;
	char switches[128];

	struct tri_diag diag;
	struct tri_mesh_build build;

	triangleio_init(&in);
	triangleio_init(&out);
	tri_diag_clear(&diag);
	tri_mesh_build_init(&build);

	if (out_mesh) {
		*out_mesh = NULL;
	}

	err = tri_validate_inputs(pslg, spec, &diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_build_switches(&spec->opts, switches, sizeof(switches));
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_pslg_to_triangle_input(pslg, &spec->opts, &in, &diag);
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
		err = JNL_MESH_ERR_TRIANGLE_FAILED;
		goto cleanup;
	}

	if (triangle_mesh_copy(ctx, &out, 1, 1) != 0) {
		err = JNL_MESH_ERR_TRIANGLE_FAILED;
		goto cleanup;
	}

	err = tri_output_to_build(&out, spec, &build, &diag);
	if (err != JNL_MESH_OK)
		goto cleanup;

	err = tri_commit_mesh(&build, spec, out_mesh);
	if (err != JNL_MESH_OK)
		goto cleanup;

cleanup:
	tri_mesh_build_free(&build);
	triangleio_free_input(&in);
	triangleio_free_output(&out);

	if (ctx) {
		triangle_context_destroy(ctx);
	}

	if (err != JNL_MESH_OK && out_mesh && *out_mesh) {
		jnl_mesh_free(*out_mesh);
		*out_mesh = NULL;
	}

	return err;
}
