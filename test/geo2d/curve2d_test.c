#include "jnl/test.h"
#include "geo2d/curve2d.h"

#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define EPS 1e-10

//
// Helpers
//

static void assert_near(f64 a, f64 b) { NEAR_F64(a, b, EPS); }

static void assert_vec_near(jnl_vec2d v, f64 x, f64 y)
{
	NEAR_F64(v.x, x, EPS);
	NEAR_F64(v.y, y, EPS);
}

static void assert_curve_ok(const struct jnl_curve2d *c)
{
	enum jnl_curve2d_err err = jnl_curve2d_check(c);

	CHECK_MSG(err == JNL_CURVE2D_OK, "check failed: %s",
	          jnl_curve2d_err_str(err));
}

//
// Tests
//

static void test_line_eval_length_and_sample(void)
{
	struct jnl_curve2d c = jnl_curve2d_line_xy(0.0, 0.0, 2.0, 4.0);

	assert_curve_ok(&c);

	assert_vec_near(jnl_curve2d_start(&c), 0.0, 0.0);
	assert_vec_near(jnl_curve2d_end(&c), 2.0, 4.0);
	assert_vec_near(jnl_curve2d_eval(&c, 0.5), 1.0, 2.0);

	assert_near(jnl_curve2d_length(&c), sqrt(20.0));

	jnl_vec2d pts[3];
	enum jnl_curve2d_err err = jnl_curve2d_sample_uniform_param(&c, 3, pts);

	CHECK_MSG(err == JNL_CURVE2D_OK, "sample failed: %s",
	          jnl_curve2d_err_str(err));

	assert_vec_near(pts[0], 0.0, 0.0);
	assert_vec_near(pts[1], 1.0, 2.0);
	assert_vec_near(pts[2], 2.0, 4.0);

	jnl_curve2d_free(&c);
}

static void test_arc_eval_and_length(void)
{
	struct jnl_curve2d c = jnl_curve2d_arc_xy(0.0, 0.0, 2.0, 0.0, M_PI / 2.0);

	assert_curve_ok(&c);

	assert_vec_near(jnl_curve2d_start(&c), 2.0, 0.0);
	assert_vec_near(jnl_curve2d_end(&c), 0.0, 2.0);
	assert_vec_near(jnl_curve2d_eval(&c, 0.5), sqrt(2.0), sqrt(2.0));

	assert_near(jnl_curve2d_length(&c), M_PI);

	jnl_vec2d pts[3];
	enum jnl_curve2d_err err = jnl_curve2d_sample_uniform_arclen(&c, 3, pts);

	CHECK_MSG(err == JNL_CURVE2D_OK, "sample failed: %s",
	          jnl_curve2d_err_str(err));

	assert_vec_near(pts[0], 2.0, 0.0);
	assert_vec_near(pts[1], sqrt(2.0), sqrt(2.0));
	assert_vec_near(pts[2], 0.0, 2.0);

	jnl_curve2d_free(&c);
}

static void test_polyline_copies_points_and_builds_length_table(void)
{
	jnl_vec2d p[3] = {
	    {.x = 0.0, .y = 0.0},
	    {.x = 3.0, .y = 0.0},
	    {.x = 3.0, .y = 4.0},
	};

	struct jnl_curve2d c;
	enum jnl_curve2d_err err = jnl_curve2d_polyline(&c, p, 3);

	CHECK_MSG(err == JNL_CURVE2D_OK, "polyline failed: %s",
	          jnl_curve2d_err_str(err));
	assert_curve_ok(&c);

	// Confirm it copied the input points.
	p[1].x = 300.0;

	EQ_I32(c.polyline.n, 3);
	NOT_NULL(c.polyline.p);
	NOT_NULL(c.polyline.s);

	assert_vec_near(c.polyline.p[0], 0.0, 0.0);
	assert_vec_near(c.polyline.p[1], 3.0, 0.0);
	assert_vec_near(c.polyline.p[2], 3.0, 4.0);

	assert_near(c.polyline.s[0], 0.0);
	assert_near(c.polyline.s[1], 3.0);
	assert_near(c.polyline.s[2], 7.0);
	assert_near(jnl_curve2d_length(&c), 7.0);

	jnl_curve2d_free(&c);
}

static void test_polyline_param_vs_arclen_eval(void)
{
	jnl_vec2d p[3] = {
	    {.x = 0.0, .y = 0.0},
	    {.x = 3.0, .y = 0.0},
	    {.x = 3.0, .y = 4.0},
	};

	struct jnl_curve2d c;
	enum jnl_curve2d_err err = jnl_curve2d_polyline(&c, p, 3);

	CHECK_MSG(err == JNL_CURVE2D_OK, "polyline failed: %s",
	          jnl_curve2d_err_str(err));

	// Native polyline parameter is by point index.
	assert_vec_near(jnl_curve2d_eval(&c, 0.5), 3.0, 0.0);

	// Arc-length parameter is by physical distance.
	// 3.5/7.0 lies 0.5 units up the vertical segment.
	assert_vec_near(jnl_curve2d_eval_arclen(&c, 0.5), 3.0, 0.5);

	jnl_curve2d_free(&c);
}

static void test_chain_clones_children_and_lengths_by_child_length(void)
{
	struct jnl_curve2d parts[2];

	parts[0] = jnl_curve2d_line_xy(0.0, 0.0, 3.0, 0.0);
	parts[1] = jnl_curve2d_line_xy(3.0, 0.0, 3.0, 4.0);

	struct jnl_curve2d c;
	enum jnl_curve2d_err err = jnl_curve2d_chain(&c, parts, 2);

	CHECK_MSG(err == JNL_CURVE2D_OK, "chain failed: %s",
	          jnl_curve2d_err_str(err));
	assert_curve_ok(&c);

	EQ_I32(c.chain.n, 2);
	NOT_NULL(c.chain.curves);
	NOT_NULL(c.chain.s);

	assert_near(c.chain.s[0], 0.0);
	assert_near(c.chain.s[1], 3.0);
	assert_near(c.chain.s[2], 7.0);
	assert_near(jnl_curve2d_length(&c), 7.0);

	assert_vec_near(jnl_curve2d_start(&c), 0.0, 0.0);
	assert_vec_near(jnl_curve2d_end(&c), 3.0, 4.0);

	// Native chain parameter is by child index.
	assert_vec_near(jnl_curve2d_eval(&c, 0.25), 1.5, 0.0);
	assert_vec_near(jnl_curve2d_eval(&c, 0.75), 3.0, 2.0);

	// Arc-length parameter is by total chain distance.
	assert_vec_near(jnl_curve2d_eval_arclen(&c, 3.5 / 7.0), 3.0, 0.5);

	jnl_curve2d_free(&c);

	// parts are value curves, but this should still be safe.
	jnl_curve2d_free(&parts[0]);
	jnl_curve2d_free(&parts[1]);
}

static void test_clone_is_deep_for_polyline(void)
{
	jnl_vec2d p[2] = {
	    {.x = 0.0, .y = 0.0},
	    {.x = 1.0, .y = 0.0},
	};

	struct jnl_curve2d a;
	enum jnl_curve2d_err err = jnl_curve2d_polyline(&a, p, 2);

	CHECK_MSG(err == JNL_CURVE2D_OK, "polyline failed: %s",
	          jnl_curve2d_err_str(err));

	struct jnl_curve2d b;
	err = jnl_curve2d_clone(&b, &a);

	CHECK_MSG(err == JNL_CURVE2D_OK, "clone failed: %s",
	          jnl_curve2d_err_str(err));

	assert_curve_ok(&a);
	assert_curve_ok(&b);

	CHECK(a.polyline.p != b.polyline.p);
	CHECK(a.polyline.s != b.polyline.s);

	a.polyline.p[1].x = 10.0;
	a.polyline.s[1] = 10.0;

	assert_vec_near(b.polyline.p[1], 1.0, 0.0);
	assert_near(b.polyline.s[1], 1.0);
	assert_near(jnl_curve2d_length(&b), 1.0);

	jnl_curve2d_free(&a);
	jnl_curve2d_free(&b);
}

static void test_reversed_returns_deep_reversed_copy(void)
{
	jnl_vec2d p[3] = {
	    {.x = 0.0, .y = 0.0},
	    {.x = 3.0, .y = 0.0},
	    {.x = 3.0, .y = 4.0},
	};

	struct jnl_curve2d a;
	enum jnl_curve2d_err err = jnl_curve2d_polyline(&a, p, 3);

	CHECK_MSG(err == JNL_CURVE2D_OK, "polyline failed: %s",
	          jnl_curve2d_err_str(err));

	struct jnl_curve2d b;
	err = jnl_curve2d_reversed(&b, &a);

	CHECK_MSG(err == JNL_CURVE2D_OK, "reversed failed: %s",
	          jnl_curve2d_err_str(err));

	assert_curve_ok(&a);
	assert_curve_ok(&b);

	CHECK(a.polyline.p != b.polyline.p);
	CHECK(a.polyline.s != b.polyline.s);

	assert_vec_near(jnl_curve2d_start(&a), 0.0, 0.0);
	assert_vec_near(jnl_curve2d_end(&a), 3.0, 4.0);

	assert_vec_near(jnl_curve2d_start(&b), 3.0, 4.0);
	assert_vec_near(jnl_curve2d_end(&b), 0.0, 0.0);

	assert_vec_near(jnl_curve2d_eval_arclen(&b, 0.5), 3.0, 0.5);

	jnl_curve2d_free(&a);
	jnl_curve2d_free(&b);
}

static void test_reverse_inplace(void)
{
	struct jnl_curve2d c = jnl_curve2d_line_xy(0.0, 0.0, 2.0, 0.0);

	assert_vec_near(jnl_curve2d_start(&c), 0.0, 0.0);
	assert_vec_near(jnl_curve2d_end(&c), 2.0, 0.0);

	jnl_curve2d_reverse_inplace(&c);

	assert_vec_near(jnl_curve2d_start(&c), 2.0, 0.0);
	assert_vec_near(jnl_curve2d_end(&c), 0.0, 0.0);

	jnl_curve2d_free(&c);
}

static void test_distributions(void)
{
	struct jnl_dist1d uniform = jnl_dist1d_uniform();
	struct jnl_dist1d cosine = jnl_dist1d_cosine_both();
	struct jnl_dist1d geom_start = jnl_dist1d_geom_start(2.0);
	struct jnl_dist1d geom_end = jnl_dist1d_geom_end(2.0);

	CHECK(jnl_dist1d_check(&uniform) == JNL_CURVE2D_OK);
	CHECK(jnl_dist1d_check(&cosine) == JNL_CURVE2D_OK);
	CHECK(jnl_dist1d_check(&geom_start) == JNL_CURVE2D_OK);
	CHECK(jnl_dist1d_check(&geom_end) == JNL_CURVE2D_OK);

	assert_near(jnl_dist1d_eval(&uniform, 0, 5), 0.0);
	assert_near(jnl_dist1d_eval(&uniform, 2, 5), 0.5);
	assert_near(jnl_dist1d_eval(&uniform, 4, 5), 1.0);

	assert_near(jnl_dist1d_eval(&cosine, 0, 5), 0.0);
	assert_near(jnl_dist1d_eval(&cosine, 2, 5), 0.5);
	assert_near(jnl_dist1d_eval(&cosine, 4, 5), 1.0);

	assert_near(jnl_dist1d_eval(&geom_start, 0, 5), 0.0);
	assert_near(jnl_dist1d_eval(&geom_start, 1, 5), 1.0 / 15.0);
	assert_near(jnl_dist1d_eval(&geom_start, 2, 5), 3.0 / 15.0);
	assert_near(jnl_dist1d_eval(&geom_start, 3, 5), 7.0 / 15.0);
	assert_near(jnl_dist1d_eval(&geom_start, 4, 5), 1.0);

	assert_near(jnl_dist1d_eval(&geom_end, 0, 5), 0.0);
	assert_near(jnl_dist1d_eval(&geom_end, 1, 5), 8.0 / 15.0);
	assert_near(jnl_dist1d_eval(&geom_end, 2, 5), 12.0 / 15.0);
	assert_near(jnl_dist1d_eval(&geom_end, 3, 5), 14.0 / 15.0);
	assert_near(jnl_dist1d_eval(&geom_end, 4, 5), 1.0);
}

static void test_sampling_with_geometric_distribution(void)
{
	struct jnl_curve2d c = jnl_curve2d_line_xy(0.0, 0.0, 1.0, 0.0);
	struct jnl_dist1d d = jnl_dist1d_geom_start(2.0);

	jnl_vec2d pts[5];
	enum jnl_curve2d_err err = jnl_curve2d_sample_dist_arclen(&c, 5, &d, pts);

	CHECK_MSG(err == JNL_CURVE2D_OK, "sample failed: %s",
	          jnl_curve2d_err_str(err));

	assert_vec_near(pts[0], 0.0, 0.0);
	assert_vec_near(pts[1], 1.0 / 15.0, 0.0);
	assert_vec_near(pts[2], 3.0 / 15.0, 0.0);
	assert_vec_near(pts[3], 7.0 / 15.0, 0.0);
	assert_vec_near(pts[4], 1.0, 0.0);

	jnl_curve2d_free(&c);
}

static void test_invalid_polyline_rejected(void)
{
	jnl_vec2d p_same[2] = {
	    {.x = 1.0, .y = 1.0},
	    {.x = 1.0, .y = 1.0},
	};

	struct jnl_curve2d c;
	enum jnl_curve2d_err err = jnl_curve2d_polyline(&c, p_same, 2);

	CHECK_MSG(err == JNL_CURVE2D_ERR_DEGENERATE,
	          "expected degenerate polyline, got: %s",
	          jnl_curve2d_err_str(err));
}

//
// Main
//

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("curve2d");

	JNL_TEST(&t, test_line_eval_length_and_sample);
	JNL_TEST(&t, test_arc_eval_and_length);
	JNL_TEST(&t, test_polyline_copies_points_and_builds_length_table);
	JNL_TEST(&t, test_polyline_param_vs_arclen_eval);
	JNL_TEST(&t, test_chain_clones_children_and_lengths_by_child_length);
	JNL_TEST(&t, test_clone_is_deep_for_polyline);
	JNL_TEST(&t, test_reversed_returns_deep_reversed_copy);
	JNL_TEST(&t, test_reverse_inplace);
	JNL_TEST(&t, test_distributions);
	JNL_TEST(&t, test_sampling_with_geometric_distribution);
	JNL_TEST(&t, test_invalid_polyline_rejected);

	return jnl_test_end(&t);
}
