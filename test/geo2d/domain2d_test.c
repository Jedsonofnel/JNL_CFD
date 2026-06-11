// geo2d/domain2d_test.c
// <jed@nelson.ac>

#include "jnl/test.h"
#include "geo2d/domain2d.h"
#include "geo2d/curve2d.h"

#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define EPS 1e-9

//
// Geometry helpers
//

// Closed CCW unit square [0,1]×[0,1] as a chain of four lines.
static struct jnl_curve2d make_unit_square(void)
{
	struct jnl_curve2d parts[4];
	parts[0] = jnl_curve2d_line_xy(0.0, 0.0, 1.0, 0.0);
	parts[1] = jnl_curve2d_line_xy(1.0, 0.0, 1.0, 1.0);
	parts[2] = jnl_curve2d_line_xy(1.0, 1.0, 0.0, 1.0);
	parts[3] = jnl_curve2d_line_xy(0.0, 1.0, 0.0, 0.0);

	struct jnl_curve2d c;
	enum jnl_curve2d_err e = jnl_curve2d_chain(&c, parts, 4);
	CHECK_MSG(e == JNL_CURVE2D_OK, "make_unit_square chain: %s",
	          jnl_curve2d_err_str(e));
	for (int i = 0; i < 4; i++)
		jnl_curve2d_free(&parts[i]);
	return c;
}

// Closed CCW rectangle [0,w]×[0,h] as a chain of four lines.
static struct jnl_curve2d make_rect(f64 w, f64 h)
{
	struct jnl_curve2d parts[4];
	parts[0] = jnl_curve2d_line_xy(0.0, 0.0, w, 0.0);
	parts[1] = jnl_curve2d_line_xy(w, 0.0, w, h);
	parts[2] = jnl_curve2d_line_xy(w, h, 0.0, h);
	parts[3] = jnl_curve2d_line_xy(0.0, h, 0.0, 0.0);

	struct jnl_curve2d c;
	enum jnl_curve2d_err e = jnl_curve2d_chain(&c, parts, 4);
	CHECK_MSG(e == JNL_CURVE2D_OK, "make_rect chain: %s",
	          jnl_curve2d_err_str(e));
	for (int i = 0; i < 4; i++)
		jnl_curve2d_free(&parts[i]);
	return c;
}

// Circle as a chain of four CCW quarter arcs.
static struct jnl_curve2d make_circle(f64 cx, f64 cy, f64 r)
{
	struct jnl_curve2d parts[4];
	f64 q = M_PI / 2.0;
	for (int i = 0; i < 4; i++)
		parts[i] = jnl_curve2d_arc_xy(cx, cy, r, i * q, (i + 1) * q);

	struct jnl_curve2d c;
	enum jnl_curve2d_err e = jnl_curve2d_chain(&c, parts, 4);
	CHECK_MSG(e == JNL_CURVE2D_OK, "make_circle chain: %s",
	          jnl_curve2d_err_str(e));
	for (int i = 0; i < 4; i++)
		jnl_curve2d_free(&parts[i]);
	return c;
}

// Self-intersecting closed polyline (figure-eight).
// Segments (0,0)→(2,2) and (2,0)→(0,2) properly intersect at (1,1).
static struct jnl_curve2d make_figure_eight(void)
{
	jnl_vec2d pts[5] = {
	    {.x = 0.0, .y = 0.0}, {.x = 2.0, .y = 2.0}, {.x = 2.0, .y = 0.0},
	    {.x = 0.0, .y = 2.0}, {.x = 0.0, .y = 0.0},
	};
	struct jnl_curve2d c;
	enum jnl_curve2d_err e = jnl_curve2d_polyline(&c, pts, 5);
	CHECK_MSG(e == JNL_CURVE2D_OK, "make_figure_eight polyline: %s",
	          jnl_curve2d_err_str(e));
	return c;
}

// Assert that d passes jnl_domain2d_check, failing the current test if not.
static void assert_domain_ok(const struct jnl_domain2d *d)
{
	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(d, &msg);
	CHECK_MSG(err == JNL_DOMAIN2D_OK, "domain check failed: %s",
	          msg ? msg : "(no message)");
}

//
// Lifecycle
//

static void test_init_clones_outer(void)
{
	// Use a polyline so we can compare pointer identity.
	jnl_vec2d pts[4] = {
	    {.x = 0.0, .y = 0.0},
	    {.x = 1.0, .y = 0.0},
	    {.x = 1.0, .y = 1.0},
	    {.x = 0.0, .y = 0.0},
	};
	struct jnl_curve2d outer;
	enum jnl_curve2d_err ce = jnl_curve2d_polyline(&outer, pts, 4);
	CHECK_MSG(ce == JNL_CURVE2D_OK, "polyline: %s", jnl_curve2d_err_str(ce));

	struct jnl_domain2d d;
	enum jnl_domain2d_err de = jnl_domain2d_init(&d, &outer);
	CHECK_MSG(de == JNL_DOMAIN2D_OK, "init: %s", jnl_domain2d_err_str(de));

	// Domain's outer must be a separate allocation.
	CHECK(d.outer.polyline.p != outer.polyline.p);
	CHECK(d.outer.polyline.s != outer.polyline.s);

	// Mutating the original must not affect the stored copy.
	outer.polyline.p[1].x = 99.0;
	NEAR_F64(d.outer.polyline.p[1].x, 1.0, EPS);

	jnl_domain2d_free(&d);
	jnl_curve2d_free(&outer);
}

static void test_free_zeros_all_fields(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	jnl_domain2d_free(&d);

	// All pointer and count fields must be zeroed.
	NULL_PTR(d.patches);
	NULL_PTR(d.holes);
	NULL_PTR(d.regions);
	EQ_I32(d.n_patches, 0);
	EQ_I32(d.n_holes, 0);
	EQ_I32(d.n_regions, 0);
	EQ_I32(d.cap_patches, 0);
	EQ_I32(d.cap_holes, 0);
	EQ_I32(d.cap_regions, 0);
}

//
// Construction
//

static void test_add_patch_increments_count_and_clones_curve(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Use a polyline so we can compare pointers.
	jnl_vec2d pts[2] = {{.x = 0.0, .y = 0.0}, {.x = 1.0, .y = 0.0}};
	struct jnl_curve2d patch;
	jnl_curve2d_polyline(&patch, pts, 2);

	enum jnl_domain2d_err e = jnl_domain2d_add_patch(&d, "inlet", 1, &patch);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "add_patch: %s", jnl_domain2d_err_str(e));

	EQ_I32(d.n_patches, 1);
	EQ_I32(d.patches[0].marker, 1);
	STR_EQ(d.patches[0].name, "inlet");

	// Stored curve must be a separate allocation.
	CHECK(d.patches[0].curve.polyline.p != patch.polyline.p);

	// Mutating the original must not affect the stored copy.
	patch.polyline.p[1].x = 99.0;
	NEAR_F64(d.patches[0].curve.polyline.p[1].x, 1.0, EPS);

	jnl_curve2d_free(&patch);
	jnl_domain2d_free(&d);
}

static void test_add_hole_increments_count_and_clones_boundary(void)
{
	struct jnl_curve2d outer = make_rect(2.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	struct jnl_curve2d bnd = make_circle(1.0, 1.0, 0.2);
	jnl_vec2d seed = {.x = 1.0, .y = 1.0};

	enum jnl_domain2d_err e =
	    jnl_domain2d_add_hole(&d, "cylinder", 2, &bnd, seed);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "add_hole: %s", jnl_domain2d_err_str(e));

	EQ_I32(d.n_holes, 1);
	EQ_I32(d.holes[0].marker, 2);
	STR_EQ(d.holes[0].name, "cylinder");
	NEAR_F64(d.holes[0].seed.x, 1.0, EPS);
	NEAR_F64(d.holes[0].seed.y, 1.0, EPS);

	// Chain children must be a separate allocation.
	CHECK(d.holes[0].boundary.chain.curves != bnd.chain.curves);

	jnl_curve2d_free(&bnd);
	jnl_domain2d_free(&d);
}

static void test_add_anonymous_hole_accepted(void)
{
	struct jnl_curve2d outer = make_rect(2.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	struct jnl_curve2d bnd = make_circle(1.0, 1.0, 0.2);
	jnl_vec2d seed = {.x = 1.0, .y = 1.0};

	enum jnl_domain2d_err e = jnl_domain2d_add_hole(&d, NULL, 0, &bnd, seed);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "add_hole NULL name: %s",
	          jnl_domain2d_err_str(e));

	EQ_I32(d.n_holes, 1);

	jnl_curve2d_free(&bnd);
	jnl_domain2d_free(&d);
}

static void test_add_region_stores_fields(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	jnl_vec2d seed = {.x = 0.5, .y = 0.5};
	enum jnl_domain2d_err e =
	    jnl_domain2d_add_region(&d, "fluid", 7, seed, 0.005);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "add_region: %s", jnl_domain2d_err_str(e));

	EQ_I32(d.n_regions, 1);
	EQ_I32(d.regions[0].marker, 7);
	STR_EQ(d.regions[0].name, "fluid");
	NEAR_F64(d.regions[0].seed.x, 0.5, EPS);
	NEAR_F64(d.regions[0].seed.y, 0.5, EPS);
	NEAR_F64(d.regions[0].max_area, 0.005, EPS);

	jnl_domain2d_free(&d);
}

static void test_dynamic_growth_past_initial_capacity(void)
{
	// Initial cap is 4.  Add 9 patches to trigger at least two doublings.
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	struct jnl_curve2d patch = jnl_curve2d_line_xy(0.0, 0.0, 1.0, 0.0);

	for (int i = 0; i < 9; i++) {
		enum jnl_domain2d_err e = jnl_domain2d_add_patch(&d, "p", i, &patch);
		CHECK_MSG(e == JNL_DOMAIN2D_OK, "add_patch[%d]: %s", i,
		          jnl_domain2d_err_str(e));
	}

	EQ_I32(d.n_patches, 9);

	// Markers must survive every reallocation intact.
	for (int i = 0; i < 9; i++)
		EQ_I32(d.patches[i].marker, i);

	jnl_curve2d_free(&patch);
	jnl_domain2d_free(&d);
}

//
// Validation
//

static void test_check_passes_for_valid_rectangle(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	assert_domain_ok(&d);
	jnl_domain2d_free(&d);
}

static void test_check_passes_with_hole_and_seed(void)
{
	struct jnl_curve2d outer = make_rect(2.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	struct jnl_curve2d hole = make_circle(1.0, 1.0, 0.3);
	jnl_vec2d seed = {.x = 1.0, .y = 1.0};
	jnl_domain2d_add_hole(&d, "cylinder", 1, &hole, seed);
	jnl_curve2d_free(&hole);

	assert_domain_ok(&d);
	jnl_domain2d_free(&d);
}

static void test_check_passes_with_patch_on_outer(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Bottom edge of the unit square — lies exactly on the outer boundary.
	struct jnl_curve2d patch = jnl_curve2d_line_xy(0.0, 0.0, 1.0, 0.0);
	jnl_domain2d_add_patch(&d, "bottom", 3, &patch);
	jnl_curve2d_free(&patch);

	assert_domain_ok(&d);
	jnl_domain2d_free(&d);
}

static void test_check_fails_for_open_outer(void)
{
	// A line is not closed; start != end.
	struct jnl_curve2d outer = jnl_curve2d_line_xy(0.0, 0.0, 1.0, 0.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(&d, &msg);

	CHECK_MSG(err == JNL_DOMAIN2D_ERR_NOT_CLOSED,
	          "expected NOT_CLOSED, got: %s", jnl_domain2d_err_str(err));
	NOT_NULL(msg);

	jnl_domain2d_free(&d);
}

static void test_check_fails_for_degenerate_outer(void)
{
	// p0 == p1 → arc length 0.
	struct jnl_curve2d outer = jnl_curve2d_line_xy(1.0, 1.0, 1.0, 1.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(&d, &msg);

	CHECK_MSG(err == JNL_DOMAIN2D_ERR_DEGENERATE,
	          "expected DEGENERATE, got: %s", jnl_domain2d_err_str(err));
	NOT_NULL(msg);

	jnl_domain2d_free(&d);
}

static void test_check_fails_for_unclosed_hole(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// An open line is not a valid hole boundary.
	struct jnl_curve2d bnd = jnl_curve2d_line_xy(0.2, 0.2, 0.8, 0.2);
	jnl_vec2d seed = {.x = 0.5, .y = 0.5};
	jnl_domain2d_add_hole(&d, "bad", 1, &bnd, seed);
	jnl_curve2d_free(&bnd);

	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(&d, &msg);

	CHECK_MSG(err == JNL_DOMAIN2D_ERR_HOLE_NOT_CLOSED,
	          "expected HOLE_NOT_CLOSED, got: %s", jnl_domain2d_err_str(err));
	NOT_NULL(msg);

	jnl_domain2d_free(&d);
}

static void test_check_fails_for_seed_outside_outer(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Closed circle, valid boundary — but seed is far outside the unit square.
	struct jnl_curve2d bnd = make_circle(0.5, 0.5, 0.1);
	jnl_vec2d bad_seed = {.x = 5.0, .y = 5.0};
	jnl_domain2d_add_hole(&d, "far", 1, &bnd, bad_seed);
	jnl_curve2d_free(&bnd);

	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(&d, &msg);

	CHECK_MSG(err == JNL_DOMAIN2D_ERR_INVALID_INPUT,
	          "expected INVALID_INPUT, got: %s", jnl_domain2d_err_str(err));

	jnl_domain2d_free(&d);
}

static void test_check_fails_for_patch_not_on_outer(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Diagonal in the interior of the square — nowhere near the boundary.
	struct jnl_curve2d patch = jnl_curve2d_line_xy(0.2, 0.2, 0.8, 0.8);
	jnl_domain2d_add_patch(&d, "interior", 1, &patch);
	jnl_curve2d_free(&patch);

	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(&d, &msg);

	CHECK_MSG(err == JNL_DOMAIN2D_ERR_BOUNDARY_NOT_ON_OUTER,
	          "expected BOUNDARY_NOT_ON_OUTER, got: %s",
	          jnl_domain2d_err_str(err));
	NOT_NULL(msg);

	jnl_domain2d_free(&d);
}

static void test_check_clears_msg_on_success(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Sentinel value — must be cleared to NULL on success.
	const char *msg = (const char *)0xDEAD;
	enum jnl_domain2d_err err = jnl_domain2d_check(&d, &msg);

	CHECK_MSG(err == JNL_DOMAIN2D_OK, "expected ok: %s",
	          jnl_domain2d_err_str(err));
	NULL_PTR(msg);

	jnl_domain2d_free(&d);
}

//
// Containment
//

static void test_contains_interior_point(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){.x = 0.5, .y = 0.5}, 128));
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){.x = 0.1, .y = 0.9}, 128));

	jnl_domain2d_free(&d);
}

static void test_contains_rejects_exterior_points(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){.x = 2.0, .y = 0.5}, 128));
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){.x = -0.5, .y = 0.5}, 128));
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){.x = 0.5, .y = 5.0}, 128));

	jnl_domain2d_free(&d);
}

static void test_contains_excludes_point_inside_hole(void)
{
	struct jnl_curve2d outer = make_rect(2.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	struct jnl_curve2d hole = make_circle(1.0, 1.0, 0.3);
	jnl_vec2d seed = {.x = 1.0, .y = 1.0};
	jnl_domain2d_add_hole(&d, "cyl", 1, &hole, seed);
	jnl_curve2d_free(&hole);

	// Dead centre of the hole — not in the fluid domain.
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){.x = 1.0, .y = 1.0}, 128));

	// Well away from the hole — still in the fluid domain.
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){.x = 0.2, .y = 0.2}, 128));

	jnl_domain2d_free(&d);
}

//
// Intersection queries
//

static void test_rectangle_does_not_self_intersect(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	CHECK(!jnl_domain2d_outer_self_intersects(&d, 128));
	jnl_domain2d_free(&d);
}

static void test_figure_eight_outer_self_intersects(void)
{
	// (0,0)→(2,2) and (2,0)→(0,2) cross at (1,1).
	struct jnl_curve2d outer = make_figure_eight();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	CHECK(jnl_domain2d_outer_self_intersects(&d, 128));
	jnl_domain2d_free(&d);
}

static void test_separate_holes_do_not_intersect(void)
{
	struct jnl_curve2d outer = make_rect(4.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Centres 2.4 apart, combined radii 0.4 — clearly disjoint.
	struct jnl_curve2d h0 = make_circle(0.8, 1.0, 0.2);
	struct jnl_curve2d h1 = make_circle(3.2, 1.0, 0.2);
	jnl_domain2d_add_hole(&d, "left", 1, &h0, (jnl_vec2d){.x = 0.8, .y = 1.0});
	jnl_domain2d_add_hole(&d, "right", 1, &h1, (jnl_vec2d){.x = 3.2, .y = 1.0});
	jnl_curve2d_free(&h0);
	jnl_curve2d_free(&h1);

	CHECK(!jnl_domain2d_holes_intersect(&d, 0, 1, 128));
	jnl_domain2d_free(&d);
}

static void test_overlapping_holes_intersect(void)
{
	struct jnl_curve2d outer = make_rect(4.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Centres 0.3 apart, combined radii 0.6 — deeply overlapping.
	// Analytic intersection points at x=2.0, y=1.0±0.26.
	struct jnl_curve2d h0 = make_circle(1.85, 1.0, 0.3);
	struct jnl_curve2d h1 = make_circle(2.15, 1.0, 0.3);
	jnl_domain2d_add_hole(&d, "a", 1, &h0, (jnl_vec2d){.x = 1.85, .y = 1.0});
	jnl_domain2d_add_hole(&d, "b", 1, &h1, (jnl_vec2d){.x = 2.15, .y = 1.0});
	jnl_curve2d_free(&h0);
	jnl_curve2d_free(&h1);

	CHECK(jnl_domain2d_holes_intersect(&d, 0, 1, 128));
	jnl_domain2d_free(&d);
}

static void test_curve_crossing_outer_intersects_boundary(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Starts at x=-0.5 (outside), ends at x=0.5 (inside): must cross x=0.
	struct jnl_curve2d c = jnl_curve2d_line_xy(-0.5, 0.5, 0.5, 0.5);
	CHECK(jnl_domain2d_curve_intersects_boundary(&d, &c, 64));
	jnl_curve2d_free(&c);

	jnl_domain2d_free(&d);
}

static void test_interior_curve_does_not_intersect_boundary(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Entirely inside the unit square.
	struct jnl_curve2d c = jnl_curve2d_line_xy(0.2, 0.2, 0.8, 0.8);
	CHECK(!jnl_domain2d_curve_intersects_boundary(&d, &c, 64));
	jnl_curve2d_free(&c);

	jnl_domain2d_free(&d);
}

//
// Bounding box
//

static void test_bbox_for_unit_square(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	struct jnl_aabb bb = jnl_domain2d_bbox(&d);

	// For a chain of axis-aligned lines, every sample that lands on a
	// horizontal/vertical segment has an exact coordinate, so the bbox
	// is exact up to floating-point rounding.
	NEAR_F64(bb.min_x, 0.0, EPS);
	NEAR_F64(bb.min_y, 0.0, EPS);
	NEAR_F64(bb.max_x, 1.0, EPS);
	NEAR_F64(bb.max_y, 1.0, EPS);

	jnl_domain2d_free(&d);
}

//
// Sampling
//

static void test_sample_outer_count_and_start_point(void)
{
	struct jnl_curve2d outer = make_unit_square();
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	jnl_vec2d *pts = NULL;
	i32 n = 0;
	enum jnl_domain2d_err e = jnl_domain2d_sample_outer(&d, 64, &pts, &n);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "sample_outer: %s",
	          jnl_domain2d_err_str(e));
	NOT_NULL(pts);
	EQ_I32(n, 64);

	// Arc-length parameterisation starts at the curve's start point (0, 0).
	NEAR_F64(pts[0].x, 0.0, EPS);
	NEAR_F64(pts[0].y, 0.0, EPS);

	free(pts);
	jnl_domain2d_free(&d);
}

static void test_sample_hole_count_and_start_point(void)
{
	struct jnl_curve2d outer = make_rect(2.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_curve2d_free(&outer);

	// Circle start at theta=0: (cx + r, cy) = (1.3, 1.0)
	struct jnl_curve2d hole = make_circle(1.0, 1.0, 0.3);
	jnl_vec2d seed = {.x = 1.0, .y = 1.0};
	jnl_domain2d_add_hole(&d, "cyl", 1, &hole, seed);
	jnl_curve2d_free(&hole);

	jnl_vec2d *pts = NULL;
	i32 n = 0;
	enum jnl_domain2d_err e = jnl_domain2d_sample_hole(&d, 0, 32, &pts, &n);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "sample_hole: %s", jnl_domain2d_err_str(e));
	NOT_NULL(pts);
	EQ_I32(n, 32);
	NEAR_F64(pts[0].x, 1.3, EPS);
	NEAR_F64(pts[0].y, 1.0, EPS);

	free(pts);
	jnl_domain2d_free(&d);
}

static void test_sample_all_count_and_order(void)
{
	struct jnl_curve2d outer = make_rect(2.0, 2.0);
	struct jnl_domain2d d;
	jnl_domain2d_init(&d, &outer);
	jnl_domain2d_set_default_marker(&d, 7);
	jnl_curve2d_free(&outer);

	struct jnl_curve2d hole = make_circle(1.0, 1.0, 0.3);
	jnl_vec2d seed = {.x = 1.0, .y = 1.0};
	jnl_domain2d_add_hole(&d, "cyl", 3, &hole, seed);
	jnl_curve2d_free(&hole);

	struct jnl_curve2d patch = jnl_curve2d_line_xy(0.0, 0.0, 2.0, 0.0);
	jnl_domain2d_add_patch(&d, "inlet", 5, &patch);
	jnl_curve2d_free(&patch);

	struct jnl_domain2d_sample_result *r = NULL;
	i32 count = 0;
	enum jnl_domain2d_err e = jnl_domain2d_sample_all(&d, 32, &r, &count);
	CHECK_MSG(e == JNL_DOMAIN2D_OK, "sample_all: %s", jnl_domain2d_err_str(e));
	NOT_NULL(r);

	// Layout: [0] outer  [1] hole[0]  [2] patch[0]
	EQ_I32(count, 3);

	EQ_I32(r[0].marker, 7);
	STR_EQ(r[0].name, "");
	EQ_I32(r[0].n, 32);
	NOT_NULL(r[0].pts);

	EQ_I32(r[1].marker, 3);
	STR_EQ(r[1].name, "cyl");
	NOT_NULL(r[1].pts);

	EQ_I32(r[2].marker, 5);
	STR_EQ(r[2].name, "inlet");
	NOT_NULL(r[2].pts);

	jnl_domain2d_sample_results_free(r, count);
	jnl_domain2d_free(&d);
}

//
// Main
//

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("domain2d");

	// Lifecycle
	JNL_TEST(&t, test_init_clones_outer);
	JNL_TEST(&t, test_free_zeros_all_fields);

	// Construction
	JNL_TEST(&t, test_add_patch_increments_count_and_clones_curve);
	JNL_TEST(&t, test_add_hole_increments_count_and_clones_boundary);
	JNL_TEST(&t, test_add_anonymous_hole_accepted);
	JNL_TEST(&t, test_add_region_stores_fields);
	JNL_TEST(&t, test_dynamic_growth_past_initial_capacity);

	// Validation
	JNL_TEST(&t, test_check_passes_for_valid_rectangle);
	JNL_TEST(&t, test_check_passes_with_hole_and_seed);
	JNL_TEST(&t, test_check_passes_with_patch_on_outer);
	JNL_TEST(&t, test_check_fails_for_open_outer);
	JNL_TEST(&t, test_check_fails_for_degenerate_outer);
	JNL_TEST(&t, test_check_fails_for_unclosed_hole);
	JNL_TEST(&t, test_check_fails_for_seed_outside_outer);
	JNL_TEST(&t, test_check_fails_for_patch_not_on_outer);
	JNL_TEST(&t, test_check_clears_msg_on_success);

	// Containment
	JNL_TEST(&t, test_contains_interior_point);
	JNL_TEST(&t, test_contains_rejects_exterior_points);
	JNL_TEST(&t, test_contains_excludes_point_inside_hole);

	// Intersection queries
	JNL_TEST(&t, test_rectangle_does_not_self_intersect);
	JNL_TEST(&t, test_figure_eight_outer_self_intersects);
	JNL_TEST(&t, test_separate_holes_do_not_intersect);
	JNL_TEST(&t, test_overlapping_holes_intersect);
	JNL_TEST(&t, test_curve_crossing_outer_intersects_boundary);
	JNL_TEST(&t, test_interior_curve_does_not_intersect_boundary);

	// Bounding box
	JNL_TEST(&t, test_bbox_for_unit_square);

	// Sampling
	JNL_TEST(&t, test_sample_outer_count_and_start_point);
	JNL_TEST(&t, test_sample_hole_count_and_start_point);
	JNL_TEST(&t, test_sample_all_count_and_order);

	return jnl_test_end(&t);
}
