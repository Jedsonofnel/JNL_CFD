/*
 * COUETTE
 * =======
 *
 * Manual SIMPLE-Stokes validation for lid-driven Couette flow.
 * Domain: 1x1 square, NX x NY quad cells
 * BCs: north Ux=1 (lid), south Ux=0, west/east neumann
 * Expected: Ux = y (linear), Uy = 0, p = const
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "jnl/common.h"
#include "fvm/linalg.h"
#include "fvm/field.h"
#include "fvm/bc.h"
#include "fvm/operators.h"
#include "mesh2d.h"
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
// Helpers
//

static f64 *alloc_cell(i32 n)
{
	f64 *p = calloc(n, sizeof(f64));
	if (!p) {
		fprintf(stderr, "OOM\n");
		exit(1);
	}
	return p;
}

static f64 *alloc_face(i32 n)
{
	f64 *p = calloc(n, sizeof(f64));
	if (!p) {
		fprintf(stderr, "OOM\n");
		exit(1);
	}
	return p;
}

static void copy_diag(const struct jnl_fvsys *sys, f64 *dst)
{
	memcpy(dst, sys->matrix.diag, sys->matrix.n_cells * sizeof(f64));
}

static void vtk_output(const char *prefix, i32 iter,
                       const struct jnl_mesh *mesh, const f64 *Ux,
                       const f64 *Uy, const f64 *p, const f64 *divU,
                       const f64 *inv_d)
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
	struct jnl_mesh *mesh = jnl_smesh_gen(WIDTH, HEIGHT, NX, NY);
	if (!mesh) {
		fprintf(stderr, "mesh gen failed\n");
		return 1;
	}

	i32 n_cells = mesh->topo.n_cells;
	i32 n_faces = mesh->topo.n_faces;
	i32 n_internal_faces = mesh->topo.n_internal_faces;

	printf("Couette-Stokes: %d cells, %d faces\n", n_cells, n_faces);

	// BC sets — defined once, reused throughout
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

	// scratch pool - BiCGSTAB needs 9, give 12
	i32 n_scratch = 12;
	jnl_arena *sp_arena =
	    arena_create(jnl_scratch_pool_arena_size(n_cells, n_scratch));
	struct jnl_scratch_pool *pool =
	    jnl_scratch_pool_new(n_cells, n_scratch, sp_arena);

	// Linear Systems
	u64 sys_sz = jnl_fvsys_arena_size(n_cells, n_faces);
	jnl_arena *ux_arena = arena_create(sys_sz);
	jnl_arena *uy_arena = arena_create(sys_sz);
	jnl_arena *pp_arena = arena_create(sys_sz);

	const i32 *owner = mesh->topo.owner;
	const i32 *neighbour = mesh->topo.neighbour;

	struct jnl_fvsys *ux_sys = jnl_fvsys_new(n_cells, n_faces, n_internal_faces,
	                                         owner, neighbour, ux_arena);
	struct jnl_fvsys *uy_sys = jnl_fvsys_new(n_cells, n_faces, n_internal_faces,
	                                         owner, neighbour, uy_arena);
	struct jnl_fvsys *pp_sys = jnl_fvsys_new(n_cells, n_faces, n_internal_faces,
	                                         owner, neighbour, pp_arena);

	// Cell fields
	f64 *Ux = alloc_cell(n_cells);
	f64 *Uy = alloc_cell(n_cells);
	f64 *p = alloc_cell(n_cells);
	f64 *pp = alloc_cell(n_cells);
	f64 *grad_px = alloc_cell(n_cells);
	f64 *grad_py = alloc_cell(n_cells);
	f64 *grad_ppx = alloc_cell(n_cells);
	f64 *grad_ppy = alloc_cell(n_cells);
	f64 *ap_x = alloc_cell(n_cells);
	f64 *ap_y = alloc_cell(n_cells);
	f64 *inv_d = alloc_cell(n_cells);
	f64 *divU = alloc_cell(n_cells);
	f64 *neg_src = alloc_cell(n_cells);

	// Face fields
	f64 *p_face = alloc_face(n_faces);
	f64 *pp_face = alloc_face(n_faces);
	f64 *un_mwi = alloc_face(n_faces);

	// Initialise to 1 to aovid /0 before first solve
	jnl_vec_fill(ap_x, 1.0, n_cells);
	jnl_vec_fill(ap_y, 1.0, n_cells);

	const f64 *vol = mesh->geom.cell_vol;
	const f64 *cy = mesh->geom.cell_cy;

	printf("\n%6s  %12s  %12s  %12s  %12s\n", "iter", "res_Ux", "res_Uy",
	       "res_p'", "divU_L2");

	for (i32 iter = 0; iter < MAX_ITERS; iter++) {
		// 1. Pressure face interp + gradient
		jnl_face_interp_cds(mesh, p, p_face);
		jnl_bc_set_apply_face(&p_bcs, pp_sys, mesh, p, p_face);
		jnl_grad_green_gauss(mesh, p_face, grad_px, grad_py);

		// 2. Rhie-Chow face flux
		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);
		jnl_bc_set_apply_face_normal(&ux_bcs, &uy_bcs, mesh, Ux, Uy, un_mwi);

		// 3. Ux Momentum
		jnl_fvsys_reset(ux_sys);
		jnl_laplacian_const(ux_sys, mesh, MU);
		for (i32 i = 0; i < n_cells; i++)
			neg_src[i] = -grad_px[i];
		jnl_su_field(ux_sys, mesh, neg_src);
		jnl_bc_set_apply_sys(&ux_bcs, ux_sys, mesh);

		copy_diag(ux_sys, ap_x);
		jnl_fvsys_under_relax(ux_sys, Ux, ALPHA_U);
		jnl_fvsys_solve_bicgstab_into(ux_sys, pool, Ux, 1e-6, 200);
		f64 res_Ux = jnl_fvsys_residual_norm(ux_sys, pool, Ux);

		// 4. Uy Momentum
		jnl_fvsys_reset(uy_sys);
		jnl_laplacian_const(uy_sys, mesh, MU);
		for (i32 i = 0; i < n_cells; i++)
			neg_src[i] = -grad_py[i];
		jnl_su_field(uy_sys, mesh, neg_src);
		jnl_bc_set_apply_sys(&uy_bcs, uy_sys, mesh);

		copy_diag(uy_sys, ap_y);
		jnl_fvsys_under_relax(uy_sys, Uy, ALPHA_U);
		jnl_fvsys_solve_bicgstab_into(uy_sys, pool, Uy, 1e-6, 200);
		f64 res_Uy = jnl_fvsys_residual_norm(uy_sys, pool, Uy);

		// 5. Rhie-Chow + div U
		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);
		jnl_bc_set_apply_face_normal(&ux_bcs, &uy_bcs, mesh, Ux, Uy, un_mwi);

		jnl_divergence(mesh, un_mwi, divU);

		// 6. inv_d = vol * 2 / (ap_x + ap_y)
		for (i32 i = 0; i < n_cells; i++)
			inv_d[i] = vol[i] * 2.0 / (ap_x[i] + ap_y[i]);

		// 7. Pressure correction p'
		jnl_vec_zero(pp, n_cells);
		jnl_fvsys_reset(pp_sys);
		jnl_laplacian_field(pp_sys, mesh, inv_d);
		for (i32 i = 0; i < n_cells; i++)
			neg_src[i] = -divU[i];
		jnl_su_field(pp_sys, mesh, neg_src);
		jnl_bc_set_apply_sys(&pp_bcs, pp_sys, mesh);

		jnl_fvsys_solve_cg_into(pp_sys, pool, pp, 1e-6, 500);
		f64 res_pp = jnl_fvsys_residual_norm(pp_sys, pool, pp);

		// 8. Corrections
		jnl_face_interp_cds(mesh, pp, pp_face);
		jnl_bc_set_apply_face(&pp_bcs, pp_sys, mesh, pp, pp_face);
		jnl_grad_green_gauss(mesh, pp_face, grad_ppx, grad_ppy);

		for (i32 i = 0; i < n_cells; i++) {
			Ux[i] -= vol[i] * grad_ppx[i] / ap_x[i];
			Uy[i] -= vol[i] * grad_ppy[i] / ap_y[i];
			p[i] += ALPHA_P * pp[i];
		}

		// Reporting
		f64 divU_L2 = jnl_vec_norm_l2(divU, n_cells);

		if (iter % PRINT_EVERY == 0)
			printf("%6d  %12.4e  %12.4e  %12.4e  %12.4e\n", iter, res_Ux,
			       res_Uy, res_pp, divU_L2);

		if (iter % VTK_EVERY == 0)
			vtk_output("out/couette", iter, mesh, Ux, Uy, p, divU, inv_d);

		// Convergence
		if (res_Ux < TOL_U && res_Uy < TOL_U && divU_L2 < TOL_P) {
			printf("\nConverged at iter %d\n", iter);
			printf("  res_Ux=%.3e  res_Uy=%.3e  divU=%.3e\n", res_Ux, res_Uy,
			       divU_L2);
			vtk_output("out/couette", iter, mesh, Ux, Uy, p, divU, inv_d);
			break;
		}
	}

	// Analytical check Ux = y
	printf("\nAnalytical comparison (Ux = y):\n");
	f64 err_max = 0.0;
	for (i32 i = 0; i < n_cells; i++) {
		f64 err = fabs(Ux[i] - cy[i]);
		if (err > err_max)
			err_max = err;
	}
	printf("  max |Ux - y| = %.6e  (expect < 0.01 for %dx%d)\n", err_max, NX,
	       NY);

	// Diagonal sanity
	printf("\nDiagonal sanity:\n");
	printf("  ap_x:  min=%.4e  max=%.4e\n", jnl_vec_min(ap_x, n_cells),
	       jnl_vec_max(ap_x, n_cells));
	printf("  ap_y:  min=%.4e  max=%.4e\n", jnl_vec_min(ap_y, n_cells),
	       jnl_vec_max(ap_y, n_cells));
	printf("  inv_d: min=%.4e  max=%.4e\n", jnl_vec_min(inv_d, n_cells),
	       jnl_vec_max(inv_d, n_cells));

	// Cleanup
	jnl_mesh_free(mesh);
	arena_destroy(sp_arena);
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
	free(p_face);
	free(pp_face);
	free(un_mwi);

	return EXIT_SUCCESS;
}
