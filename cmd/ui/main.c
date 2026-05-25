#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <math.h>

#include "jnl/common.h"
#include "geo2d.h"
#include "mesh2d.h"
#include "ui.h"

static jnl_ui_handle *g_ui = NULL;

static void cleanup(int sig)
{
	(void)sig;
	if (g_ui) {
		jnl_ui_close(g_ui);
		jnl_ui_free(g_ui);
		g_ui = NULL;
	}
	exit(0);
}

static void pslg_add_circle_hole(struct jnl_pslg *g, double cx, double cy,
                                 double r, i32 marker, int n_seg)
{
	u32 base = g->nodes.len;

	for (int i = 0; i < n_seg; i++) {
		double a = 2.0 * M_PI * i / n_seg;
		jnl_pslg_node_add(g, cx + r * cos(a), cy + r * sin(a), 0);
	}

	for (int i = 0; i < n_seg; i++) {
		jnl_pslg_edge_add(g, base + i, base + (i + 1) % n_seg, marker);
	}

	jnl_pslg_hole_add(g, cx, cy);
}

int main(void)
{
	signal(SIGINT, cleanup);
	signal(SIGTERM, cleanup);

	/*
	 * L-shape, same as before:
	 *
	 *   3-----------2
	 *   |           |
	 *   |  (upper)  |
	 *   |           |
	 *   4----5      |        <- dividing line at y=250
	 *        | (lo) |
	 *        0------1
	 *
	 *   x: 100..500,  y: 100..400
	 *   Inner corner at (300, 250).
	 *
	 * The dividing line runs from (300,250) to (500,250),
	 * splitting the lower-right rectangle into two named regions:
	 *   "upper" above y=250, "lower" below y=250.
	 *
	 * A circular hole sits in the upper region.
	 * A finer sub-region box sits in the lower region.
	 */

#define M_WALL 1
#define M_INLET 2
#define M_OUTLET 3
#define M_HOLE 4
#define M_DIVIDER 5

	struct jnl_pslg pslg = {0};
	jnl_pslg_init(&pslg);

	/* Outer L boundary */
	u32 v0 = jnl_pslg_node_add(&pslg, 300.0, 100.0, 0);
	u32 v1 = jnl_pslg_node_add(&pslg, 500.0, 100.0, 0);
	u32 v2 = jnl_pslg_node_add(&pslg, 500.0, 400.0, 0);
	u32 v3 = jnl_pslg_node_add(&pslg, 100.0, 400.0, 0);
	u32 v4 = jnl_pslg_node_add(&pslg, 100.0, 250.0, 0);
	u32 v5 = jnl_pslg_node_add(&pslg, 300.0, 250.0, 0);

	jnl_pslg_edge_add(&pslg, v0, v1, M_WALL);
	jnl_pslg_edge_add(&pslg, v1, v2, M_OUTLET);
	jnl_pslg_edge_add(&pslg, v2, v3, M_WALL);
	jnl_pslg_edge_add(&pslg, v3, v4, M_INLET);
	jnl_pslg_edge_add(&pslg, v4, v5, M_WALL);
	jnl_pslg_edge_add(&pslg, v5, v0, M_WALL);

	/*
	 * Dividing line from v5=(300,250) to a new node at (500,250).
	 * Uses M_DIVIDER so it's a named internal segment but not a baffle.
	 * We re-use v5 and add one new node on the right wall.
	 */
	u32 v6 = jnl_pslg_node_add(&pslg, 500.0, 250.0, 0);
	jnl_pslg_edge_add(&pslg, v5, v6, M_DIVIDER);

	/*
	 * Circular hole in the upper region, centred at (300, 330), r=40.
	 * 16 segments is plenty for this scale.
	 */
	pslg_add_circle_hole(&pslg, 300.0, 330.0, 40.0, M_HOLE, 16);

	/*
	 * Region seeds.  Triangle propagates the marker from the seed
	 * outward until it hits a constrained segment.
	 *
	 * upper: above the divider, seed at (250, 330)
	 * lower: below the divider, seed at (400, 175)
	 *
	 * Give the lower region a tighter area constraint so we can see
	 * the mesh density change across the dividing line.
	 */
	jnl_pslg_region_add(&pslg, 250.0, 330.0, 1, 800.0); /* upper, coarse */
	jnl_pslg_region_add(&pslg, 400.0, 175.0, 2, 200.0); /* lower, fine   */

	/* Mesh spec */
	struct jnl_tri_mesh_spec spec = jnl_tri_mesh_spec_default();
	spec.opts = jnl_tri_opts_set_min_angle(spec.opts, 20.0);
	/* No global area -- let per-region areas drive refinement */
	spec.opts = jnl_tri_opts_enable_region_areas(spec.opts, true);

	jnl_tri_tags_add_patch(&spec.tags, M_WALL, "wall");
	jnl_tri_tags_add_patch(&spec.tags, M_INLET, "inlet");
	jnl_tri_tags_add_patch(&spec.tags, M_OUTLET, "outlet");
	jnl_tri_tags_add_patch(&spec.tags, M_HOLE, "hole_wall");
	jnl_tri_tags_add_patch(&spec.tags, M_DIVIDER, "divider");
	jnl_tri_tags_add_region(&spec.tags, 1, "upper");
	jnl_tri_tags_add_region(&spec.tags, 2, "lower");

	struct jnl_mesh *mesh = NULL;
	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&pslg, &spec, &mesh);
	if (err != JNL_MESH_OK) {
		fprintf(stderr, "Triangulation failed (err=%d)\n", err);
		jnl_pslg_free(&pslg);
		jnl_tri_tags_free(&spec.tags);
		return 1;
	}

	printf("Triangulated: %d vertices, %d cells, %d faces\n",
	       mesh->topo.n_vertices, mesh->topo.n_cells, mesh->topo.n_faces);
	printf("Regions:\n");
	for (i32 i = 0; i < mesh->regions.n_regions; i++) {
		printf("  %s: %d cells\n", mesh->regions.data[i].name,
		       mesh->regions.data[i].n_cells);
	}
	printf("Patches:\n");
	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		printf("  %s: %d faces\n", mesh->patches.data[i].name,
		       mesh->patches.data[i].n_faces);
	}

	g_ui = jnl_ui_spawn();
	if (!g_ui) {
		fprintf(stderr, "Failed to spawn UI\n");
		jnl_mesh_free(mesh);
		jnl_pslg_free(&pslg);
		jnl_tri_tags_free(&spec.tags);
		return 1;
	}

	usleep(200000);

	if (jnl_ui_send_pslg(g_ui, &pslg) < 0)
		fprintf(stderr, "Failed to send PSLG\n");
	else
		printf("PSLG sent\n");

	sleep(3);

	if (jnl_ui_send_mesh(g_ui, mesh) < 0)
		fprintf(stderr, "Failed to send mesh\n");
	else
		printf("Mesh sent\n");

	sleep(15);

	printf("Closing window...\n");
	jnl_ui_close(g_ui);
	jnl_ui_free(g_ui);
	g_ui = NULL;

	jnl_mesh_free(mesh);
	jnl_pslg_free(&pslg);
	jnl_tri_tags_free(&spec.tags);

	return 0;
}
