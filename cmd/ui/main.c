#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
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

int main(void)
{
	signal(SIGINT, cleanup);
	signal(SIGTERM, cleanup);

	struct jnl_pslg pslg = {0};
	jnl_pslg_init(&pslg);
	jnl_pslg_node_add(&pslg, 10, 10, 0);
	jnl_pslg_node_add(&pslg, 10, 300, 0);
	jnl_pslg_node_add(&pslg, 200, 200, 0);
	jnl_pslg_node_add(&pslg, 200, 10, 0);
	jnl_pslg_node_add(&pslg, 100, 96, 0);
	jnl_pslg_node_add(&pslg, 500, 96, 0);
	jnl_pslg_edge_add(&pslg, 0, 1, 0);
	jnl_pslg_edge_add(&pslg, 1, 2, 0);
	jnl_pslg_edge_add(&pslg, 2, 3, 0);
	jnl_pslg_edge_add(&pslg, 3, 0, 0);
	jnl_pslg_edge_add(&pslg, 3, 4, 0);
	jnl_pslg_edge_add(&pslg, 3, 5, 0);

	struct jnl_mesh *mesh = jnl_smesh_gen(500.0, 300.0, 20, 12);
	if (!mesh) {
		fprintf(stderr, "Failed to generate mesh\n");
		return 1;
	}

	g_ui = jnl_ui_spawn();
	if (!g_ui) {
		fprintf(stderr, "Failed to spawn UI\n");
		return 1;
	}

	usleep(200000);

	if (jnl_ui_send_pslg(g_ui, &pslg) < 0)
		fprintf(stderr, "Failed to send PSLG\n");
	else
		printf("PSLG sent\n");

	sleep(10);

	if (jnl_ui_send_mesh(g_ui, mesh) < 0)
		fprintf(stderr, "Failed to send mesh\n");
	else
		printf("Mesh sent (%d vertices, %d faces)\n", mesh->topo.n_vertices,
		       mesh->topo.n_faces);

	sleep(10);

	printf("Closing window...\n");
	jnl_ui_close(g_ui);
	jnl_ui_free(g_ui);
	g_ui = NULL;

	jnl_pslg_free(&pslg);
	jnl_mesh_free(mesh);
	return 0;
}
