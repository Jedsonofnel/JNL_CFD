/*
 * COUETTE
 * =======
 *
 * SIMPLE-Stokes validation for lid-driven Couette flow.
 *
 * Domain: 1x1 square, NX x NY quad cells
 * BCs:
 *   north: Ux=1, Uy=0
 *   south: Ux=0, Uy=0
 *   west/east: zero-gradient U
 *   p: zero-gradient everywhere
 *
 * Expected:
 *   Ux = y
 *   Uy = 0
 *   p = const
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jnl/common.h"
#include "mesh2d.h"
#include "mesh2d/cartmesh2d.h"

#include "fvm/linalg.h"
#include "fvm/solver.h"
#include "fvm/field.h"
#include "fvm/bc.h"
#include "fvm/operators.h"

#include "vtk.h"
#include "vec.h"
#include "scratch.h"

#define NX 20
#define NY 20
#define WIDTH 1.0
#define HEIGHT 1.0

#define MU 0.01

#define ALPHA_U 0.7
#define ALPHA_P 0.3

#define MAX_ITERS 2000
#define PRINT_EVERY 25
#define VTK_EVERY 200

#define TOL_U 1e-5
#define TOL_P 1e-5

//
// Allocation helpers
//

static f64 *alloc_f64(i32 n)
{
	f64 *p = calloc((size_t)n, sizeof(f64));
	if (!p) {
		fprintf(stderr, "OOM\n");
		exit(EXIT_FAILURE);
	}
	return p;
}

//
// BC refresh helpers
//

static void fill_velocity_ghosts(const pmsh2d *mesh, f64 *Ux, f64 *Uy,
                                 const struct jnl_bc_set *ux_bcs,
                                 const struct jnl_bc_set *uy_bcs)
{
	jnl_bc_set_fill(ux_bcs, mesh, Ux);
	jnl_bc_set_fill(uy_bcs, mesh, Uy);
}

static void fill_pressure_ghosts(const pmsh2d *mesh, f64 *p,
                                 const struct jnl_bc_set *p_bcs)
{
	jnl_bc_set_fill(p_bcs, mesh, p);
}

//
// VTK output
//

static void vtk_output(const char *prefix, i32 iter, const pmsh2d *mesh,
                       const f64 *Ux, const f64 *Uy, const f64 *p,
                       const f64 *divU, const f64 *inv_d)
{
	char path[256];
	snprintf(path, sizeof(path), "%s_%04d.vtk", prefix, iter);

	struct jnl_vtk_scalar scalars[] = {
	    {"p", p},
	    {"divU", divU},
	    {"inv_d", inv_d},
	    {NULL, NULL},
	};

	struct jnl_vtk_vector vectors[] = {
	    {"U", Ux, Uy},
	    {NULL, NULL, NULL},
	};

	jnl_vtk_write(path, mesh, scalars, vectors);
}

//
// Main
//

int main(void)
{
	struct jnl_cartmesh2d_opts opts = jnl_cartmesh2d_opts_default();

	opts.x0 = 0.0;
	opts.y0 = 0.0;
	opts.width = WIDTH;
	opts.height = HEIGHT;
	opts.nx = NX;
	opts.ny = NY;

	pmsh2d *mesh = NULL;
	enum jnl_mesh_err mesh_err = jnl_cartmesh2d_build(&opts, &mesh);

	if (mesh_err != JNL_MESH_OK || !mesh) {
		fprintf(stderr, "mesh build failed: %s\n", jnl_mesh_err_str(mesh_err));
		return EXIT_FAILURE;
	}

	const i32 n_cells = mesh->topo.n_cells;     // real + ghost
	const i32 n_real = mesh->topo.n_real_cells; // solved cells
	const i32 n_faces = mesh->topo.n_faces;

	printf("Couette-Stokes: %d real cells, %d total cells, %d faces\n", n_real,
	       n_cells, n_faces);

	//
	// BC sets
	//

	static const struct jnl_bc_entry ux_entries[] = {
	    JNL_BC_D("north", 1.0),
	    JNL_BC_D("south", 0.0),
	    JNL_BC_N("west", 0.0),
	    JNL_BC_N("east", 0.0),
	};

	static const struct jnl_bc_entry uy_entries[] = {
	    JNL_BC_D("north", 0.0),
	    JNL_BC_D("south", 0.0),
	    JNL_BC_N("west", 0.0),
	    JNL_BC_N("east", 0.0),
	};

	static const struct jnl_bc_set ux_bcs = JNL_BC_SET(ux_entries, 4);
	static const struct jnl_bc_set uy_bcs = JNL_BC_SET(uy_entries, 4);
	static const struct jnl_bc_set p_bcs = JNL_BC_SET_ALL(JNL_BC_NEUMANN, 0.0);
	static const struct jnl_bc_set pp_bcs = JNL_BC_SET_ALL(JNL_BC_NEUMANN, 0.0);

	//
	// Scratch pool
	//

	struct jnl_scratch_pool *pool = jnl_scratch_pool_new(n_cells);

	//
	// Linear systems
	//

	const u64 sys_sz = jnl_fvsys_arena_size(mesh);

	jnl_arena *ux_arena = arena_create(sys_sz);
	jnl_arena *uy_arena = arena_create(sys_sz);
	jnl_arena *pp_arena = arena_create(sys_sz);

	struct jnl_fvsys *ux_sys = jnl_fvsys_new(mesh, ux_arena);
	struct jnl_fvsys *uy_sys = jnl_fvsys_new(mesh, uy_arena);
	struct jnl_fvsys *pp_sys = jnl_fvsys_new(mesh, pp_arena);

	//
	// Full-cell fields: [n_cells]
	//

	f64 *Ux = alloc_f64(n_cells);
	f64 *Uy = alloc_f64(n_cells);
	f64 *p = alloc_f64(n_cells);
	f64 *pp = alloc_f64(n_cells);

	f64 *grad_px = alloc_f64(n_cells);
	f64 *grad_py = alloc_f64(n_cells);
	f64 *grad_ppx = alloc_f64(n_cells);
	f64 *grad_ppy = alloc_f64(n_cells);

	f64 *ap_x = alloc_f64(n_cells);
	f64 *ap_y = alloc_f64(n_cells);
	f64 *inv_d = alloc_f64(n_cells);

	f64 *divU = alloc_f64(n_cells);
	f64 *neg_src = alloc_f64(n_cells);

	//
	// Face fields: [n_faces]
	//

	f64 *un_mwi = alloc_f64(n_faces);

	//
	// Initial field values / ghosts
	//

	jnl_vec_fill(ap_x, 1.0, n_cells);
	jnl_vec_fill(ap_y, 1.0, n_cells);

	fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);
	fill_pressure_ghosts(mesh, p, &p_bcs);
	fill_pressure_ghosts(mesh, pp, &pp_bcs);

	const f64 *vol = mesh->geom.cell_vol;
	const f64 *cy = mesh->geom.cell_cy;

	printf("\n%6s  %12s  %12s  %12s  %12s\n", "iter", "res_Ux", "res_Uy",
	       "res_p'", "divU_L2");

	for (i32 iter = 0; iter < MAX_ITERS; iter++) {
		//
		// 1. Pressure gradient.
		//

		fill_pressure_ghosts(mesh, p, &p_bcs);
		jnl_grad_gg(mesh, p, grad_px, grad_py);

		//
		// 2. Rhie-Chow face flux using full-cell fields.
		//

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);
		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);

		//
		// 3. Ux momentum.
		//

		jnl_fvsys_reset(ux_sys);

		jnl_laplacian_k(ux_sys, mesh, MU);

		for (i32 c = 0; c < n_real; c++)
			neg_src[c] = -grad_px[c];

		jnl_su_v_f(ux_sys, mesh, neg_src);

		jnl_bc_set_close(&ux_bcs, ux_sys, mesh);
		jnl_bc_assert_all_closed(ux_sys);

		jnl_fvsys_under_relax(ux_sys, Ux, ALPHA_U);
		jnl_diag_snapshot(mesh, ux_sys, ap_x);
		jnl_fvsys_solve_bicgstab_dilu_into(ux_sys, pool, Ux, 1e-6, 200);

		f64 res_Ux = jnl_fvsys_residual_norm(ux_sys, pool, Ux);

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);

		//
		// 4. Uy momentum.
		//

		jnl_fvsys_reset(uy_sys);

		jnl_laplacian_k(uy_sys, mesh, MU);

		for (i32 c = 0; c < n_real; c++)
			neg_src[c] = -grad_py[c];

		jnl_su_v_f(uy_sys, mesh, neg_src);

		jnl_bc_set_close(&uy_bcs, uy_sys, mesh);
		jnl_bc_assert_all_closed(uy_sys);

		jnl_fvsys_under_relax(uy_sys, Uy, ALPHA_U);
		jnl_diag_snapshot(mesh, uy_sys, ap_y);
		jnl_fvsys_solve_bicgstab_dilu_into(uy_sys, pool, Uy, 1e-6, 200);

		f64 res_Uy = jnl_fvsys_residual_norm(uy_sys, pool, Uy);

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);

		//
		// 5. Recompute Rhie-Chow flux and integrated divergence.
		//

		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);

		/*
		 * Pressure correction RHS wants integrated mass imbalance.
		 */
		jnl_divergence_i(mesh, un_mwi, divU);

		//
		// 6. inv_d = vol * 2 / (ap_x + ap_y)
		//

		for (i32 c = 0; c < n_real; c++)
			inv_d[c] = vol[c] * 2.0 / (ap_x[c] + ap_y[c]);

		jnl_ghost_copy(mesh, inv_d);

		//
		// 7. Pressure correction p'.
		//

		jnl_vec_zero(pp, n_cells);

		jnl_fvsys_reset(pp_sys);

		jnl_laplacian_f(pp_sys, mesh, inv_d);

		for (i32 c = 0; c < n_real; c++)
			neg_src[c] = -divU[c];

		jnl_su_i_f(pp_sys, mesh, neg_src);

		jnl_bc_set_close(&pp_bcs, pp_sys, mesh);
		jnl_bc_assert_all_closed(pp_sys);

		jnl_fvsys_solve_cg_dic_into(pp_sys, pool, pp, 1e-6, 500);

		f64 res_pp = jnl_fvsys_residual_norm(pp_sys, pool, pp);

		fill_pressure_ghosts(mesh, pp, &pp_bcs);

		//
		// 8. Corrections.
		//

		jnl_grad_gg(mesh, pp, grad_ppx, grad_ppy);

		for (i32 c = 0; c < n_real; c++) {
			Ux[c] -= vol[c] * grad_ppx[c] / ap_x[c];
			Uy[c] -= vol[c] * grad_ppy[c] / ap_y[c];
			p[c] += ALPHA_P * pp[c];
		}

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);
		fill_pressure_ghosts(mesh, p, &p_bcs);

		//
		// Reporting.
		//

		f64 divU_L2 = jnl_vec_norm_l2(divU, n_real);

		if (iter % PRINT_EVERY == 0) {
			printf("%6d  %12.4e  %12.4e  %12.4e  %12.4e\n", iter, res_Ux,
			       res_Uy, res_pp, divU_L2);
		}

		if (iter % VTK_EVERY == 0)
			vtk_output("out/couette", iter, mesh, Ux, Uy, p, divU, inv_d);

		if (res_Ux < TOL_U && res_Uy < TOL_U && divU_L2 < TOL_P) {
			printf("\nConverged at iter %d\n", iter);
			printf("  res_Ux=%.3e  res_Uy=%.3e  divU=%.3e\n", res_Ux, res_Uy,
			       divU_L2);
			vtk_output("out/couette", iter, mesh, Ux, Uy, p, divU, inv_d);
			break;
		}
	}

	//
	// Analytical check Ux = y on real cells only.
	//

	printf("\nAnalytical comparison (Ux = y):\n");

	f64 err_max = 0.0;
	for (i32 c = 0; c < n_real; c++) {
		f64 err = fabs(Ux[c] - cy[c]);
		if (err > err_max)
			err_max = err;
	}

	printf("  max |Ux - y| = %.6e  (expect < 0.01 for %dx%d)\n", err_max, NX,
	       NY);

	printf("\nDiagonal sanity:\n");
	printf("  ap_x:  min=%.4e  max=%.4e\n", jnl_vec_min(ap_x, n_real),
	       jnl_vec_max(ap_x, n_real));
	printf("  ap_y:  min=%.4e  max=%.4e\n", jnl_vec_min(ap_y, n_real),
	       jnl_vec_max(ap_y, n_real));
	printf("  inv_d: min=%.4e  max=%.4e\n", jnl_vec_min(inv_d, n_real),
	       jnl_vec_max(inv_d, n_real));

	//
	// Cleanup.
	//

	jnl_polymesh2d_free(mesh);

	arena_destroy(ux_arena);
	arena_destroy(uy_arena);
	arena_destroy(pp_arena);

	free(Ux);
	free(Uy);
	free(p);
	free(pp);
	free(grad_px);
	free(grad_py);
	free(grad_ppx);
	free(grad_ppy);
	free(ap_x);
	free(ap_y);
	free(inv_d);
	free(divU);
	free(neg_src);
	free(un_mwi);

	return EXIT_SUCCESS;
}
