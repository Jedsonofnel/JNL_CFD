// test/fvm.c
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "jnl/test.h"
#include "mesh2d.h"
#include "fvm/linalg.h"
#include "fvm/operators.h"
#include "fvm/bc.h"

// Mesh: thin 1D bar — 1 cell tall, nx cells wide
// Width L=1, height=1/nx so cells are square-ish
#define NX 80
#define NY 1
#define L 1.0
#define H (L / NX)
#define TOL_DIFF 1e-10 // diffusion-only: should be near machine zero
#define TOL_CONV 1e-3  // convection-diffusion: CDS has truncation error

static struct jnl_mesh *make_mesh(void) { return jnl_smesh_gen(L, H, NX, NY); }

// Allocate a zeroed cell field
static f64 *cell_field(i32 n)
{
	f64 *f = calloc(n, sizeof(f64));
	if (!f) {
		fprintf(stderr, "OOM\n");
		exit(1);
	}
	return f;
}

// ============================================================
// Test 1: Pure diffusion, Dirichlet both ends
// T_west=1, T_east=0, gamma=1
// Analytical: T(x) = 1 - x/L
// ============================================================
static void test_diffusion_dirichlet(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *fa = arena_create(jnl_fvsys_arena_size(n, n_conn) +
	                             jnl_solver_ctx_arena_size(n));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, fa);
	struct jnl_solver_ctx *ctx = jnl_solver_ctx_new(n, fa);

	jnl_laplacian_const(sys, mesh, 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "west", 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "east", 0.0);

	f64 *T = cell_field(n);
	jnl_fvsys_solve_cg(sys, ctx, T, 1e-12, 0);

	for (i32 i = 0; i < n; i++) {
		f64 x = mesh->geom.cell_cx[i];
		f64 T_exact = 1.0 - x / L;
		f64 err = fabs(T[i] - T_exact);
		TEST_ASSERT_MSG(
		    err < TOL_DIFF,
		    "diffusion_dirichlet: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e", i,
		    x, T[i], T_exact, err);
	}

	free(T);
	arena_destroy(fa);
	jnl_mesh_free(mesh);
	printf("PASS test_diffusion_dirichlet\n");
}

// ============================================================
// Test 2: Diffusion, Dirichlet west + zero-flux Neumann east
// T_west=1, dT/dx=0 east, gamma=1
// Analytical: T(x) = 1 (uniform)
// ============================================================
static void test_diffusion_neumann(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *fa = arena_create(jnl_fvsys_arena_size(n, n_conn) +
	                             jnl_solver_ctx_arena_size(n));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, fa);
	struct jnl_solver_ctx *ctx = jnl_solver_ctx_new(n, fa);

	jnl_laplacian_const(sys, mesh, 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "west", 1.0);
	jnl_bc_neumann_const(sys, mesh, "east", 0.0);

	f64 *T = cell_field(n);
	jnl_fvsys_solve_cg(sys, ctx, T, 1e-12, 0);

	for (i32 i = 0; i < n; i++) {
		f64 err = fabs(T[i] - 1.0);
		TEST_ASSERT_MSG(err < TOL_DIFF,
		                "diffusion_neumann: cell %d T=%.6f err=%.2e", i, T[i],
		                err);
	}

	free(T);
	arena_destroy(fa);
	jnl_mesh_free(mesh);
	printf("PASS test_diffusion_neumann\n");
}

// ============================================================
// Test 3: Diffusion with uniform volumetric source
// gamma=1, S=1, T_west=0, T_east=0
// Analytical: T(x) = S/(2*gamma) * x*(L-x)
// ============================================================
static void test_diffusion_source(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *fa = arena_create(jnl_fvsys_arena_size(n, n_conn) +
	                             jnl_solver_ctx_arena_size(n));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, fa);
	struct jnl_solver_ctx *ctx = jnl_solver_ctx_new(n, fa);

	const f64 gamma = 1.0;
	const f64 S = 1.0;

	jnl_laplacian_const(sys, mesh, gamma);
	jnl_su_const(sys, mesh, S);
	jnl_bc_dirichlet_const(sys, mesh, "west", 0.0);
	jnl_bc_dirichlet_const(sys, mesh, "east", 0.0);

	f64 *T = cell_field(n);
	jnl_fvsys_solve_cg(sys, ctx, T, 1e-12, 0);

	for (i32 i = 0; i < n; i++) {
		f64 x = mesh->geom.cell_cx[i];
		f64 T_exact = (S / (2.0 * gamma)) * x * (L - x);
		f64 err = fabs(T[i] - T_exact);
		TEST_ASSERT_MSG(
		    err < 1e-4,
		    "diffusion_source: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e", i, x,
		    T[i], T_exact, err);
	}

	free(T);
	arena_destroy(fa);
	jnl_mesh_free(mesh);
	printf("PASS test_diffusion_source\n");
}

// ============================================================
// Test 4: Convection-diffusion, CDS, Pe < 2
// rho*u=const, gamma=1, T_west=1, T_east=0
// Analytical: T(x) = (exp(Pe*x/L) - 1) / (exp(Pe) - 1)  [normalised 0->1]
// then shifted: T(x) = 1 - (exp(Pe*x/L)-1)/(exp(Pe)-1)  for T_W=1,T_E=0
// ============================================================
static void test_conv_diff_cds(void)
{
	const f64 gamma = 1.0;
	const f64 rho_u = 1.0;
	const f64 Pe = rho_u * L / gamma;
	const f64 exp_Pe = exp(Pe);

	f64 errors[2];
	i32 nxs[2] = {40, 80};

	for (i32 run = 0; run < 2; run++) {
		i32 nx = nxs[run];
		f64 h = L / nx;

		struct jnl_mesh *mesh = jnl_smesh_gen(L, h, nx, NY);
		i32 n = mesh->topo.n_cells;
		i32 n_conn = mesh->topo.n_faces;

		jnl_arena *fa = arena_create(jnl_fvsys_arena_size(n, n_conn) +
		                             jnl_solver_ctx_arena_size(n) +
		                             (u64)n_conn * sizeof(f64));
		struct jnl_fvsys *sys = jnl_fvsys_new(n, n_conn, mesh->topo.owner,
		                                      mesh->topo.neighbour, fa);
		struct jnl_solver_ctx *ctx = jnl_solver_ctx_new(n, fa);

		f64 *u_normal = ARENA_PUSH_ARRAY_Z(fa, f64, n_conn);
		for (i32 f = 0; f < n_conn; f++)
			u_normal[f] = rho_u * mesh->geom.face_nx[f];

		jnl_laplacian_const(sys, mesh, gamma);
		jnl_div_cds_const(sys, mesh, 1.0, u_normal);
		jnl_bc_dirichlet_const(sys, mesh, "west", 1.0);
		jnl_bc_dirichlet_const(sys, mesh, "east", 0.0);

		f64 *T = cell_field(n);

		jnl_fvsys_solve_bicgstab(sys, ctx, T, 1e-12, 0);

		// L2 error over all cells
		f64 sum = 0.0;
		for (i32 i = 0; i < n; i++) {
			f64 x = mesh->geom.cell_cx[i];
			f64 T_exact = 1.0 - (exp(Pe * x / L) - 1.0) / (exp_Pe - 1.0);
			f64 e = T[i] - T_exact;
			sum += e * e * mesh->geom.cell_vol[i];
		}
		errors[run] = sqrt(sum);

		free(T);
		arena_destroy(fa);
		jnl_mesh_free(mesh);
	}

	// CDS is second-order: halving h should reduce L2 error by ~4
	f64 rate = log(errors[0] / errors[1]) / log(2.0);
	TEST_ASSERT_MSG(
	    rate > 1.8,
	    "conv_diff_cds: convergence rate %.2f < 1.8 (expected ~2.0) "
	    "errors: coarse=%.2e fine=%.2e",
	    rate, errors[0], errors[1]);

	printf("PASS test_conv_diff_cds (rate=%.2f, errors: %.2e -> %.2e)\n", rate,
	       errors[0], errors[1]);
}

// ============================================================
// Test 5: Convection-diffusion, UDS, higher Pe
// Same setup as CDS but Pe=10 (CDS would be unstable).
// UDS is first-order so tolerance is looser — just check monotonicity
// and boundary values, not pointwise accuracy.
// ============================================================
static void test_conv_diff_uds(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *fa =
	    arena_create(jnl_fvsys_arena_size(n, n_conn) +
	                 jnl_solver_ctx_arena_size(n) + (u64)n_conn * sizeof(f64));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, fa);
	struct jnl_solver_ctx *ctx = jnl_solver_ctx_new(n, fa);

	const f64 gamma = 1.0;
	const f64 rho_u = 10.0; // Pe=10

	f64 *u_normal = ARENA_PUSH_ARRAY_Z(fa, f64, n_conn);
	for (i32 f = 0; f < n_conn; f++) {
		f64 nx = mesh->geom.face_nx[f];
		u_normal[f] = nx > 0.5 ? rho_u : 0.0;
	}

	jnl_laplacian_const(sys, mesh, gamma);
	jnl_div_uds_const(sys, mesh, 1.0, u_normal);
	jnl_bc_dirichlet_const(sys, mesh, "west", 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "east", 0.0);

	f64 *T = cell_field(n);
	jnl_fvsys_solve_bicgstab(sys, ctx, T, 1e-12, 0);

	// Check solution is bounded and monotonically decreasing west->east
	TEST_ASSERT_MSG(T[0] <= 1.0 + 1e-6 && T[0] >= 0.0,
	                "conv_diff_uds: T[0]=%.6f out of bounds", T[0]);
	TEST_ASSERT_MSG(T[n - 1] >= -1e-6 && T[n - 1] <= 1.0,
	                "conv_diff_uds: T[n-1]=%.6f out of bounds", T[n - 1]);

	for (i32 i = 1; i < n; i++) {
		TEST_ASSERT_MSG(
		    T[i] <= T[i - 1] + 1e-6,
		    "conv_diff_uds: non-monotone at cell %d: T[%d]=%.6f > T[%d]=%.6f",
		    i, i, T[i], i - 1, T[i - 1]);
	}

	// Also compare against analytical — UDS numerical diffusion gives
	// effective Pe_eff = Pe/(1 + Pe*h/(2*L)), so solution is still exponential
	// but we only assert loose tolerance
	f64 exp_Pe = exp(rho_u * L / gamma);
	for (i32 i = 0; i < n; i++) {
		f64 x = mesh->geom.cell_cx[i];
		f64 T_exact = 1.0 - (exp(rho_u * x / gamma) - 1.0) / (exp_Pe - 1.0);
		f64 err = fabs(T[i] - T_exact);
		TEST_ASSERT_MSG(
		    err < 0.1,
		    "conv_diff_uds: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e", i, x,
		    T[i], T_exact, err);
	}

	free(T);
	arena_destroy(fa);
	jnl_mesh_free(mesh);
	printf("PASS test_conv_diff_uds\n");
}

// ============================================================
// Test 6: Two-region diffusion (field gamma)
// gamma_left=1, gamma_right=10, T_west=0, T_east=1
// Analytical: piecewise linear, slope inversely proportional to gamma.
// Flux continuity: gamma_L * dT/dx = gamma_R * dT/dx = q (const)
// q = (T_E - T_W) / (L_left/gamma_L + L_right/gamma_R)
// ============================================================
static void test_diffusion_field_gamma(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *fa =
	    arena_create(jnl_fvsys_arena_size(n, n_conn) +
	                 jnl_solver_ctx_arena_size(n) + (u64)n * sizeof(f64));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, fa);
	struct jnl_solver_ctx *ctx = jnl_solver_ctx_new(n, fa);

	const f64 gamma_L = 1.0;
	const f64 gamma_R = 10.0;
	const f64 x_mid = 0.5 * L;

	f64 *gamma = ARENA_PUSH_ARRAY_Z(fa, f64, n);
	for (i32 i = 0; i < n; i++)
		gamma[i] = mesh->geom.cell_cx[i] < x_mid ? gamma_L : gamma_R;

	jnl_laplacian_field(sys, mesh, gamma);
	jnl_bc_dirichlet_const(sys, mesh, "west", 0.0);
	jnl_bc_dirichlet_const(sys, mesh, "east", 1.0);

	f64 *T = cell_field(n);
	jnl_fvsys_solve_cg(sys, ctx, T, 1e-12, 0);

	// Analytical
	f64 q = 1.0 / (x_mid / gamma_L + (L - x_mid) / gamma_R);
	for (i32 i = 0; i < n; i++) {
		f64 x = mesh->geom.cell_cx[i];
		f64 T_exact = x < x_mid
		                  ? q * x / gamma_L
		                  : q * x_mid / gamma_L + q * (x - x_mid) / gamma_R;
		f64 err = fabs(T[i] - T_exact);
		TEST_ASSERT_MSG(
		    err < 1e-2,
		    "diffusion_field_gamma: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e",
		    i, x, T[i], T_exact, err);
	}

	free(T);
	arena_destroy(fa);
	jnl_mesh_free(mesh);
	printf("PASS test_diffusion_field_gamma\n");
}

// ============================================================
// Test 7: Diagonal dominance and positive diagonals
// Just check that a well-posed diffusion system has good matrix properties
// ============================================================
static void test_matrix_properties(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *fa = arena_create(jnl_fvsys_arena_size(n, n_conn));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, fa);

	jnl_laplacian_const(sys, mesh, 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "west", 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "east", 0.0);

	TEST_ASSERT_MSG(jnl_fvsys_all_diagonals_positive(sys),
	                "matrix_properties: non-positive diagonal");
	TEST_ASSERT_MSG(jnl_fvsys_diagonal_dominance(sys) >= 1.0,
	                "matrix_properties: diagonal dominance ratio %.4f < 1",
	                jnl_fvsys_diagonal_dominance(sys));
	TEST_ASSERT_MSG(
	    jnl_fvsys_max_asymmetry(sys) < 1e-12,
	    "matrix_properties: asymmetry %.2e (diffusion should be symmetric)",
	    jnl_fvsys_max_asymmetry(sys));

	arena_destroy(fa);
	jnl_mesh_free(mesh);
	printf("PASS test_matrix_properties\n");
}

// ============================================================

int main(void)
{
	test_diffusion_dirichlet();
	test_diffusion_neumann();
	test_diffusion_source();
	test_conv_diff_cds();
	test_conv_diff_uds();
	test_diffusion_field_gamma();
	test_matrix_properties();

	TEST_PASS();
	return 0;
}
