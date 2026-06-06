#ifndef JNL_TRIMESH2D_H
#define JNL_TRIMESH2D_H

#include <stdbool.h>

#include "jnl/common.h"
#include "pslg2d.h"
#include "polymesh2d.h"

//
// Triangle options
//

enum jnl_tri_quality_mode {
	JNL_TRIANGLE_QUALITY_NONE = 0,
	JNL_TRIANGLE_QUALITY_MIN_ANGLE,
};

struct jnl_tri_opts {
	bool preserve_segments;
	bool conforming_delaunay;

	enum jnl_tri_quality_mode quality_mode;
	f64 min_angle_deg;

	bool use_global_max_area;
	f64 global_max_area;

	bool use_region_areas;

	bool zero_based_numbering;

	bool quiet;
	bool verbose;
};

struct jnl_tri_opts jnl_tri_opts_default(void);

struct jnl_tri_opts jnl_tri_opts_set_min_angle(struct jnl_tri_opts opts,
                                               f64 min_angle_deg);

struct jnl_tri_opts jnl_tri_opts_set_global_max_area(struct jnl_tri_opts opts,
                                                     f64 max_area);

struct jnl_tri_opts jnl_tri_opts_set_cell_count(struct jnl_tri_opts opts,
                                                const struct jnl_pslg *pslg,
                                                i32 target_cells);

struct jnl_tri_opts jnl_tri_opts_set_resolution(struct jnl_tri_opts opts,
                                                const struct jnl_pslg *pslg,
                                                f64 resolution);

struct jnl_tri_opts jnl_tri_opts_enable_region_areas(struct jnl_tri_opts opts,
                                                     bool enabled);

struct jnl_tri_opts
jnl_tri_opts_set_conforming_delaunay(struct jnl_tri_opts opts, bool enabled);

struct jnl_tri_opts jnl_tri_opts_set_quiet(struct jnl_tri_opts opts,
                                           bool enabled);

//
// Triangle marker metadata
//

struct jnl_tri_marker_name {
	i32 marker;
	char name[JNL_PMSH2D_NAME_CAP];
};

struct jnl_tri_marker_map {
	struct jnl_tri_marker_name *data;
	u32 len, cap;
};

struct jnl_tri_tags {
	struct jnl_tri_marker_map patches;
	struct jnl_tri_marker_map baffles;
	struct jnl_tri_marker_map regions;

	bool require_named_patches;
	bool require_named_baffles;
	bool require_named_regions;
};

struct jnl_tri_mesh_spec {
	struct jnl_tri_opts opts;
	struct jnl_tri_tags tags;
};

struct jnl_tri_mesh_spec jnl_tri_mesh_spec_default(void);

void jnl_tri_tags_init(struct jnl_tri_tags *tags);
void jnl_tri_tags_free(struct jnl_tri_tags *tags);

enum jnl_mesh_err jnl_tri_tags_add_patch(struct jnl_tri_tags *tags, i32 marker,
                                         const char *name);

enum jnl_mesh_err jnl_tri_tags_add_baffle(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name);

enum jnl_mesh_err jnl_tri_tags_add_region(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name);

const char *jnl_tri_tags_find_patch(const struct jnl_tri_tags *tags,
                                    i32 marker);

const char *jnl_tri_tags_find_baffle(const struct jnl_tri_tags *tags,
                                     i32 marker);

const char *jnl_tri_tags_find_region(const struct jnl_tri_tags *tags,
                                     i32 marker);

bool jnl_tri_tags_is_baffle_marker(const struct jnl_tri_tags *tags, i32 marker);

//
// Triangle generation from PSLG
//

enum jnl_mesh_err
jnl_trimesh2d_desc_from_pslg(const struct jnl_pslg *pslg,
                             const struct jnl_tri_mesh_spec *spec,
                             struct jnl_polymesh2d_desc **out_desc);

enum jnl_mesh_err jnl_trimesh2d_from_pslg(const struct jnl_pslg *pslg,
                                          const struct jnl_tri_mesh_spec *spec,
                                          struct jnl_polymesh2d **out_mesh);

#endif
