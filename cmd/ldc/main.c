/*
 * LID-DRIVEN CAVITY
 * =================
 *
 * SIMPLE-with-convection validation for the 2-D square lid-driven cavity.
 *
 * Domain: L x L square, NX x NY quad cells
 *
 * BCs:
 *   north/lid: Ux=U_LID, Uy=0
 *   west/east/south: no-slip Ux=Uy=0
 *   pressure / pressure-correction: all Neumann, singular and pinned by linalg
 *
 * Target: Ghia et al. high-Re benchmark, Re = 7500.
 * Re = rho * U_LID * L / mu, so MU is derived below from RE.
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

#define NX 129
#define NY 129

#define LENGTH 1.0
#define HEIGHT 1.0

#define U_LID 1.0
#define RHO 1.0
#define RE 7500.0
#define MU (RHO * U_LID * LENGTH / RE)

#define ALPHA_U 0.5
#define ALPHA_P 0.1

#define MAX_ITERS 15000
#define PRINT_EVERY 100
#define VTK_EVERY 500

#define TOL_U 1e-6
#define TOL_P 1e-6

// linalg options
#define MOM_TOL 1e-4
#define PP_TOL 1e-4
#define MOM_LIN_ITERS 10
#define PP_LIN_ITERS 10

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
// BC helpers
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

static void close_scalar_bcs(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             const struct jnl_bc_set *bcs)
{
	jnl_bc_set_close(bcs, sys, mesh);
	jnl_bc_assert_all_closed(sys);
}

//
// VTK output
//

static void vtk_output(const char *prefix, i32 iter, const pmsh2d *mesh,
                       const f64 *Ux, const f64 *Uy, const f64 *p,
                       const f64 *divU, const f64 *inv_d)
{
	char path[256];
	snprintf(path, sizeof(path), "%s%.0f_%04d.vtk", prefix, RE, iter);

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
// Ghia-style centreline samples
//

static i32 nearest_cell_on_vertical_centreline(const pmsh2d *mesh, f64 y)
{
	const f64 *cx = mesh->geom.cell_cx;
	const f64 *cy = mesh->geom.cell_cy;

	i32 best = 0;
	f64 best_d2 = HUGE_VAL;

	for (i32 c = 0; c < mesh->topo.n_real_cells; c++) {
		f64 dx = cx[c] - 0.5 * LENGTH;
		f64 dy = cy[c] - y;
		f64 d2 = dx * dx + dy * dy;

		if (d2 < best_d2) {
			best_d2 = d2;
			best = c;
		}
	}

	return best;
}

static i32 nearest_cell_on_horizontal_centreline(const pmsh2d *mesh, f64 x)
{
	const f64 *cx = mesh->geom.cell_cx;
	const f64 *cy = mesh->geom.cell_cy;

	i32 best = 0;
	f64 best_d2 = HUGE_VAL;

	for (i32 c = 0; c < mesh->topo.n_real_cells; c++) {
		f64 dx = cx[c] - x;
		f64 dy = cy[c] - 0.5 * HEIGHT;
		f64 d2 = dx * dx + dy * dy;

		if (d2 < best_d2) {
			best_d2 = d2;
			best = c;
		}
	}

	return best;
}

static void print_centerline_samples(const pmsh2d *mesh, const f64 *Ux,
                                     const f64 *Uy)
{
	static const f64 ghia_y[] = {
	    1.0000, 0.9766, 0.9688, 0.9609, 0.9531, 0.8516, 0.7344, 0.6172, 0.5000,
	    0.4531, 0.2813, 0.1719, 0.1016, 0.0703, 0.0625, 0.0547, 0.0000,
	};

	static const f64 ghia_x[] = {
	    1.0000, 0.9688, 0.9609, 0.9531, 0.9453, 0.9063, 0.8594, 0.8047, 0.5000,
	    0.2344, 0.2266, 0.1563, 0.0938, 0.0781, 0.0703, 0.0625, 0.0000,
	};

	printf("\nCentreline samples for Ghia-style comparison:\n");

	printf("\n  vertical centreline, x = 0.5: u(y)\n");
	printf("  %10s  %14s\n", "y", "Ux");

	for (i32 k = 0; k < (i32)(sizeof(ghia_y) / sizeof(ghia_y[0])); k++) {
		i32 c = nearest_cell_on_vertical_centreline(mesh, ghia_y[k]);
		printf("  %10.4f  %14.7e\n", ghia_y[k], Ux[c]);
	}

	printf("\n  horizontal centreline, y = 0.5: v(x)\n");
	printf("  %10s  %14s\n", "x", "Uy");

	for (i32 k = 0; k < (i32)(sizeof(ghia_x) / sizeof(ghia_x[0])); k++) {
		i32 c = nearest_cell_on_horizontal_centreline(mesh, ghia_x[k]);
		printf("  %10.4f  %14.7e\n", ghia_x[k], Uy[c]);
	}
}

//
// Main
//

int main(void)
{
	struct jnl_cartmesh2d_opts opts = jnl_cartmesh2d_opts_default();

	opts.x0 = 0.0;
	opts.y0 = 0.0;
	opts.width = LENGTH;
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

	printf("Lid-driven cavity: %d real cells, %d total cells, %d faces\n",
	       n_real, n_cells, n_faces);
	printf("  Re=%.0f  U_lid=%.3f  rho=%.3f  mu=%.8e\n", RE, U_LID, RHO, MU);

	//
	// BC sets
	//

	static const struct jnl_bc_entry ux_entries[] = {
	    JNL_BC_D("west", 0.0),
	    JNL_BC_D("east", 0.0),
	    JNL_BC_D("north", U_LID),
	    JNL_BC_D("south", 0.0),
	};

	static const struct jnl_bc_entry uy_entries[] = {
	    JNL_BC_D("west", 0.0),
	    JNL_BC_D("east", 0.0),
	    JNL_BC_D("north", 0.0),
	    JNL_BC_D("south", 0.0),
	};

	static const struct jnl_bc_entry p_entries[] = {
	    JNL_BC_N("west", 0.0),
	    JNL_BC_N("east", 0.0),
	    JNL_BC_N("north", 0.0),
	    JNL_BC_N("south", 0.0),
	};

	static const struct jnl_bc_set ux_bcs = JNL_BC_SET(ux_entries, 4);
	static const struct jnl_bc_set uy_bcs = JNL_BC_SET(uy_entries, 4);
	static const struct jnl_bc_set p_bcs = JNL_BC_SET(p_entries, 4);
	static const struct jnl_bc_set pp_bcs = JNL_BC_SET(p_entries, 4);

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

	//
	// Face fields: [n_faces]
	//

	f64 *un_mwi = alloc_f64(n_faces);

	//
	// Initial values.
	//

	jnl_vec_fill(ap_x, 1.0, n_cells);
	jnl_vec_fill(ap_y, 1.0, n_cells);

	fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);
	fill_pressure_ghosts(mesh, p, &p_bcs);
	fill_pressure_ghosts(mesh, pp, &pp_bcs);

	const f64 *vol = mesh->geom.cell_vol;

	printf("\n%6s  %12s  %12s  %12s  %12s\n", "iter", "res_Ux", "res_Uy",
	       "res_p'", "divU_L2");

	for (i32 iter = 0; iter < MAX_ITERS; iter++) {
		//
		// 1. Pressure gradient.
		//

		fill_pressure_ghosts(mesh, p, &p_bcs);
		jnl_grad_gg(mesh, p, grad_px, grad_py);

		//
		// 2. Rhie-Chow face flux from current fields.
		//

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);
		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);

		//
		// 3. Ux momentum: diffusion + convection + pressure source.
		//

		jnl_fvsys_reset(ux_sys);

		jnl_laplacian_k(ux_sys, mesh, MU);
		jnl_div_uds_k(ux_sys, mesh, RHO, un_mwi);
		jnl_su_v_fs(ux_sys, mesh, -1.0, grad_px);

		close_scalar_bcs(ux_sys, mesh, &ux_bcs);

		jnl_diag_snapshot(mesh, ux_sys, ap_x);
		jnl_fvsys_under_relax(ux_sys, Ux, ALPHA_U);

		jnl_fvsys_solve_bicgstab_dilu_into(ux_sys, pool, Ux, MOM_TOL, MOM_LIN_ITERS);

		f64 res_Ux = jnl_fvsys_residual_norm(ux_sys, pool, Ux);

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);

		//
		// 4. Uy momentum: diffusion + convection + pressure source.
		//

		jnl_fvsys_reset(uy_sys);

		jnl_laplacian_k(uy_sys, mesh, MU);
		jnl_div_uds_k(uy_sys, mesh, RHO, un_mwi);
		jnl_su_v_fs(uy_sys, mesh, -1.0, grad_py);

		close_scalar_bcs(uy_sys, mesh, &uy_bcs);

		jnl_diag_snapshot(mesh, uy_sys, ap_y);
		jnl_fvsys_under_relax(uy_sys, Uy, ALPHA_U);

		jnl_fvsys_solve_bicgstab_dilu_into(uy_sys, pool, Uy, MOM_TOL, MOM_LIN_ITERS);

		f64 res_Uy = jnl_fvsys_residual_norm(uy_sys, pool, Uy);

		fill_velocity_ghosts(mesh, Ux, Uy, &ux_bcs, &uy_bcs);

		//
		// 5. Recompute Rhie-Chow flux and integrated divergence.
		//

		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);

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
		jnl_su_i_fs(pp_sys, mesh, -RHO, divU);

		close_scalar_bcs(pp_sys, mesh, &pp_bcs);

		jnl_fvsys_solve_cg_dic_into(pp_sys, pool, pp, PP_TOL, PP_LIN_ITERS);

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
		// 9. Recompute pressure gradient and divergence for reporting.
		//

		jnl_grad_gg(mesh, p, grad_px, grad_py);

		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);

		jnl_divergence_i(mesh, un_mwi, divU);

		//
		// Reporting.
		//

		f64 divU_L2 = jnl_vec_norm_l2(divU, n_real);

		if (iter % PRINT_EVERY == 0) {
			printf("%6d  %12.4e  %12.4e  %12.4e  %12.4e\n", iter, res_Ux,
			       res_Uy, res_pp, divU_L2);
		}

		if (iter % VTK_EVERY == 0) {
			vtk_output("out/cavity_ghia_re", iter, mesh, Ux, Uy, p, divU,
			           inv_d);
		}

		if (res_Ux < TOL_U && res_Uy < TOL_U && divU_L2 < TOL_P) {
			printf("\nConverged at iter %d\n", iter);
			printf("  res_Ux=%.3e  res_Uy=%.3e  divU=%.3e\n", res_Ux, res_Uy,
			       divU_L2);

			vtk_output("out/cavity_ghia_re", iter, mesh, Ux, Uy, p, divU,
			           inv_d);
			break;
		}
	}

	print_centerline_samples(mesh, Ux, Uy);

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
	free(un_mwi);

	return EXIT_SUCCESS;
}
