/*
 * LID-DRIVEN CAVITY
 * =================
 *
 * SIMPLE-with-convection validation for the 2-D square lid-driven cavity.
 * Domain: L x L square, NX x NY quad cells
 * BCs: north/lid Ux=U_LID, Uy=0; west/east/south no-slip (Ux=Uy=0),
 *      all-Neumann pressure / pressure-correction (singular, pinned by linalg).
 *
 * Target: Ghia et al. high-Re benchmark, Re = 7500.
 * Re = rho * U_LID * L / mu, so MU is derived below from RE.
 *
 * Notes:
 *   - Ghia et al. also tabulated Re=10000, but steady 2-D cavity flow is
 * commonly reported to lose stability around Re ~= 7.5e3-1.0e4. This case
 * therefore uses the highest Ghia tabulated Re below that range: Re=7500.
 *   - With first-order upwind convection this should be robust, but expect the
 *     primary vortex/secondary eddies to be somewhat more diffused than Ghia.
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
#define MOM_LIN_ITERS 50
#define PP_LIN_ITERS 100

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

static i32 nearest_cell_on_vertical_centreline(const struct jnl_mesh *mesh,
                                               f64 y)
{
	const f64 *cx = mesh->geom.cell_cx;
	const f64 *cy = mesh->geom.cell_cy;
	i32 n_cells = mesh->topo.n_cells;
	i32 best = 0;
	f64 best_d2 = HUGE_VAL;

	for (i32 i = 0; i < n_cells; i++) {
		f64 dx = cx[i] - 0.5 * LENGTH;
		f64 dy = cy[i] - y;
		f64 d2 = dx * dx + dy * dy;
		if (d2 < best_d2) {
			best_d2 = d2;
			best = i;
		}
	}

	return best;
}

static i32 nearest_cell_on_horizontal_centreline(const struct jnl_mesh *mesh,
                                                 f64 x)
{
	const f64 *cx = mesh->geom.cell_cx;
	const f64 *cy = mesh->geom.cell_cy;
	i32 n_cells = mesh->topo.n_cells;
	i32 best = 0;
	f64 best_d2 = HUGE_VAL;

	for (i32 i = 0; i < n_cells; i++) {
		f64 dx = cx[i] - x;
		f64 dy = cy[i] - 0.5 * HEIGHT;
		f64 d2 = dx * dx + dy * dy;
		if (d2 < best_d2) {
			best_d2 = d2;
			best = i;
		}
	}

	return best;
}

static void print_centerline_samples(const struct jnl_mesh *mesh, const f64 *Ux,
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
	struct jnl_mesh *mesh = jnl_smesh_gen(LENGTH, HEIGHT, NX, NY);
	if (!mesh) {
		fprintf(stderr, "mesh gen failed\n");
		return 1;
	}

	i32 n_cells = mesh->topo.n_cells;
	i32 n_faces = mesh->topo.n_faces;
	i32 n_conns = n_faces;

	printf("Lid-driven cavity: %d cells, %d faces\n", n_cells, n_faces);
	printf("  Re=%.0f  U_lid=%.3f  rho=%.3f  mu=%.8e\n", RE, U_LID, RHO, MU);

	// BC sets — defined once, reused throughout.
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

	// Scratch pool — BiCGSTAB needs 9, give 12
	i32 n_scratch = 12;
	jnl_arena *sp_arena =
	    arena_create(jnl_scratch_pool_arena_size(n_cells, n_scratch));
	struct jnl_scratch_pool *pool =
	    jnl_scratch_pool_new(n_cells, n_scratch, sp_arena);

	// Linear systems
	u64 sys_sz = jnl_fvsys_arena_size(n_cells, n_conns);
	jnl_arena *ux_arena = arena_create(sys_sz);
	jnl_arena *uy_arena = arena_create(sys_sz);
	jnl_arena *pp_arena = arena_create(sys_sz);

	const i32 *owner = mesh->topo.owner;
	const i32 *neighbour = mesh->topo.neighbour;

	struct jnl_fvsys *ux_sys =
	    jnl_fvsys_new(n_cells, n_conns, owner, neighbour, ux_arena);
	struct jnl_fvsys *uy_sys =
	    jnl_fvsys_new(n_cells, n_conns, owner, neighbour, uy_arena);
	struct jnl_fvsys *pp_sys =
	    jnl_fvsys_new(n_cells, n_conns, owner, neighbour, pp_arena);

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

	// Face fields
	f64 *p_face = alloc_face(n_faces);
	f64 *pp_face = alloc_face(n_faces);
	f64 *un_mwi = alloc_face(n_faces);

	// Initialise ap to 1 to avoid /0 before first solve.
	// Start from rest; the moving lid enters through the north Ux Dirichlet BC.
	jnl_vec_fill(ap_x, 1.0, n_cells);
	jnl_vec_fill(ap_y, 1.0, n_cells);

	const f64 *vol = mesh->geom.cell_vol;

	printf("\n%6s  %12s  %12s  %12s  %12s\n", "iter", "res_Ux", "res_Uy",
	       "res_p'", "divU_L2");

	for (i32 iter = 0; iter < MAX_ITERS; iter++) {
		// 1. Pressure face interp + gradient
		jnl_face_interp_cds(mesh, p, p_face);
		jnl_bc_set_apply_face(&p_bcs, mesh, p, p_face);
		jnl_grad_green_gauss(mesh, p_face, grad_px, grad_py);

		// 2. Rhie-Chow face flux
		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);
		jnl_bc_set_apply_face_normal(&ux_bcs, &uy_bcs, mesh, Ux, Uy, un_mwi);

		// 3. Ux momentum — diffusion + convection (UDS) + pressure source
		jnl_fvsys_reset(ux_sys);
		jnl_laplacian_const(ux_sys, mesh, MU);
		jnl_div_uds_const(ux_sys, mesh, RHO, un_mwi);
		jnl_su_volumetric_field_scaled(ux_sys, mesh, -1.0, grad_px);
		jnl_bc_set_apply_sys(&ux_bcs, ux_sys, mesh);

		copy_diag(ux_sys, ap_x);
		jnl_fvsys_under_relax(ux_sys, Ux, ALPHA_U);
		jnl_fvsys_solve_bicgstab_into(ux_sys, pool, Ux, MOM_TOL, MOM_LIN_ITERS);
		f64 res_Ux = jnl_fvsys_residual_norm(ux_sys, pool, Ux);

		// 4. Uy momentum — diffusion + convection (UDS) + pressure source
		jnl_fvsys_reset(uy_sys);
		jnl_laplacian_const(uy_sys, mesh, MU);
		jnl_div_uds_const(uy_sys, mesh, RHO, un_mwi);
		jnl_su_volumetric_field_scaled(uy_sys, mesh, -1.0, grad_py);
		jnl_bc_set_apply_sys(&uy_bcs, uy_sys, mesh);

		copy_diag(uy_sys, ap_y);
		jnl_fvsys_under_relax(uy_sys, Uy, ALPHA_U);
		jnl_fvsys_solve_bicgstab_into(uy_sys, pool, Uy, MOM_TOL, MOM_LIN_ITERS);
		f64 res_Uy = jnl_fvsys_residual_norm(uy_sys, pool, Uy);

		// 5. Rhie-Chow + div U (recompute after momentum update)
		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);
		jnl_bc_set_apply_face_normal(&ux_bcs, &uy_bcs, mesh, Ux, Uy, un_mwi);

		jnl_divergence_integrated(mesh, un_mwi, divU);

		// 6. inv_d = vol * 2 / (ap_x + ap_y)
		for (i32 i = 0; i < n_cells; i++)
			inv_d[i] = vol[i] * 2.0 / (ap_x[i] + ap_y[i]);

		// 7. Pressure correction p' — singular system, pinned by linalg
		jnl_vec_zero(pp, n_cells);
		jnl_fvsys_reset(pp_sys);
		jnl_laplacian_field(pp_sys, mesh, inv_d);
		jnl_su_integrated_scaled(pp_sys, mesh, -RHO, divU);
		jnl_bc_set_apply_sys(&pp_bcs, pp_sys, mesh);

		jnl_fvsys_solve_cg_into(pp_sys, pool, pp, PP_TOL, PP_LIN_ITERS);
		f64 res_pp = jnl_fvsys_residual_norm(pp_sys, pool, pp);

		// 8. Corrections
		jnl_face_interp_cds(mesh, pp, pp_face);
		jnl_bc_set_apply_face(&pp_bcs, mesh, pp, pp_face);
		jnl_grad_green_gauss(mesh, pp_face, grad_ppx, grad_ppy);

		for (i32 i = 0; i < n_cells; i++) {
			Ux[i] -= vol[i] * grad_ppx[i] / ap_x[i];
			Uy[i] -= vol[i] * grad_ppy[i] / ap_y[i];
		}

		jnl_vec_axpy(p, ALPHA_P, pp, n_cells);

		// 9. Recompute divU_L2
		jnl_face_interp_cds(mesh, p, p_face);
		jnl_bc_set_apply_face(&p_bcs, mesh, p, p_face);
		jnl_grad_green_gauss(mesh, p_face, grad_px, grad_py);

		jnl_rhie_chow(mesh, Ux, Uy, p, grad_px, grad_py, ap_x, ap_y, un_mwi);
		jnl_bc_set_apply_face_normal(&ux_bcs, &uy_bcs, mesh, Ux, Uy, un_mwi);
		jnl_divergence_integrated(mesh, un_mwi, divU);

		// Reporting
		f64 divU_L2 = jnl_vec_norm_l2(divU, n_cells);

		if (iter % PRINT_EVERY == 0)
			printf("%6d  %12.4e  %12.4e  %12.4e  %12.4e\n", iter, res_Ux,
			       res_Uy, res_pp, divU_L2);

		if (iter % VTK_EVERY == 0)
			vtk_output("out/cavity_ghia_re", iter, mesh, Ux, Uy, p, divU,
			           inv_d);

		// Convergence
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
	free(p_face);
	free(pp_face);
	free(un_mwi);

	return EXIT_SUCCESS;
}
