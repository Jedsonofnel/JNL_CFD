#include "mesh2d.h"

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
// MESH GENERATION
//

// TODO:
