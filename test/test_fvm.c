#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "jnl/test.h"
#include "mesh2d.h"
#include "fvm/linalg.h"
#include "fvm/operators.h"
#include "fvm/bc.h"
#include "fvm/ctx.h"
#include "fvm/field.h"

#define NX 80
#define NY 1
#define L 1.0
#define H (L / NX)

#define TOL_DIFF 1e-10
#define TOL_CONV 1e-3

static struct jnl_mesh *make_mesh(void) { return jnl_smesh_gen(L, H, NX, NY); }

// ============================================================
// Shared solve helper — owns ctx lifetime
// ============================================================

typedef struct {
	struct jnl_mesh *mesh;
	struct jnl_fvm_ctx *ctx;
	struct jnl_fvsys *sys;
	f64 *T;
	i32 n;
} problem;

static problem make_problem(struct jnl_mesh *mesh, i32 n_fields,
                            i32 n_face_fields, i32 n_systems)
{
	problem p;
	p.mesh = mesh;
	p.n = mesh->topo.n_cells;
	p.ctx = jnl_fvm_ctx_new(mesh, n_fields, n_face_fields, n_systems, 8, 4);
	p.sys = jnl_fvm_ctx_alloc_fvsys(p.ctx);
	p.T = calloc((u64)p.n, sizeof(f64));
	if (!p.T) {
		fprintf(stderr, "OOM\n");
		exit(1);
	}
	return p;
}

static void free_problem(problem *p)
{
	free(p->T);
	jnl_fvm_ctx_free(p->ctx);
	jnl_mesh_free(p->mesh);
}

// ============================================================
// Test 1: Pure diffusion, Dirichlet both ends
// Analytical: T(x) = 1 - x/L
// ============================================================
static void test_diffusion_dirichlet(void)
{
	problem p = make_problem(make_mesh(), 0, 0, 1);

	jnl_laplacian_const(p.sys, p.mesh, 1.0);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "west", 1.0);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "east", 0.0);
	jnl_fvsys_solve_cg(p.sys, p.ctx->cell_pool, p.T, 1e-12, 0);

	for (i32 i = 0; i < p.n; i++) {
		f64 x = p.mesh->geom.cell_cx[i];
		f64 exact = 1.0 - x / L;
		f64 err = fabs(p.T[i] - exact);
		TEST_ASSERT_MSG(
		    err < TOL_DIFF,
		    "diffusion_dirichlet: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e", i,
		    x, p.T[i], exact, err);
	}

	free_problem(&p);
	printf("PASS test_diffusion_dirichlet\n");
}

// ============================================================
// Test 2: Diffusion, Dirichlet west + zero-flux Neumann east
// Analytical: T(x) = 1 (uniform)
// ============================================================
static void test_diffusion_neumann(void)
{
	problem p = make_problem(make_mesh(), 0, 0, 1);

	jnl_laplacian_const(p.sys, p.mesh, 1.0);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "west", 1.0);
	jnl_bc_neumann_const(p.sys, p.mesh, "east", 0.0);
	jnl_fvsys_solve_cg(p.sys, p.ctx->cell_pool, p.T, 1e-12, 0);

	for (i32 i = 0; i < p.n; i++) {
		f64 err = fabs(p.T[i] - 1.0);
		TEST_ASSERT_MSG(err < TOL_DIFF,
		                "diffusion_neumann: cell %d T=%.6f err=%.2e", i, p.T[i],
		                err);
	}

	free_problem(&p);
	printf("PASS test_diffusion_neumann\n");
}

// ============================================================
// Test 3: Diffusion with uniform volumetric source
// Analytical: T(x) = S/(2*gamma) * x*(L-x)
// ============================================================
static void test_diffusion_source(void)
{
	problem p = make_problem(make_mesh(), 0, 0, 1);
	const f64 gamma = 1.0, S = 1.0;

	jnl_laplacian_const(p.sys, p.mesh, gamma);
	jnl_su_const(p.sys, p.mesh, S);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "west", 0.0);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "east", 0.0);
	jnl_fvsys_solve_cg(p.sys, p.ctx->cell_pool, p.T, 1e-12, 0);

	for (i32 i = 0; i < p.n; i++) {
		f64 x = p.mesh->geom.cell_cx[i];
		f64 exact = (S / (2.0 * gamma)) * x * (L - x);
		f64 err = fabs(p.T[i] - exact);
		TEST_ASSERT_MSG(
		    err < 1e-4,
		    "diffusion_source: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e", i, x,
		    p.T[i], exact, err);
	}

	free_problem(&p);
	printf("PASS test_diffusion_source\n");
}

// ============================================================
// Test 4: Convection-diffusion CDS, convergence rate ~2
// ============================================================
static void test_conv_diff_cds(void)
{
	const f64 gamma = 0.1, rho = 1.0, u = 1.0;
	const f64 Pe = rho * u * L / gamma;
	const f64 exp_Pe = exp(Pe);

	f64 errors[2];
	i32 nxs[2] = {40, 80};

	for (i32 run = 0; run < 2; run++) {
		i32 nx = nxs[run];
		struct jnl_mesh *mesh = jnl_smesh_gen(L, L / nx, nx, NY);
		// 2 cell fields (Ux,Uy), 3 face fields (ux,uy,un), 1 system
		problem p = make_problem(mesh, 2, 3, 1);

		f64 *Ux = jnl_fvm_ctx_alloc_field(p.ctx);
		f64 *Uy = jnl_fvm_ctx_alloc_field(p.ctx);
		f64 *ux_face = jnl_fvm_ctx_alloc_face_field(p.ctx);
		f64 *uy_face = jnl_fvm_ctx_alloc_face_field(p.ctx);
		f64 *un_face = jnl_fvm_ctx_alloc_face_field(p.ctx);

		for (i32 i = 0; i < p.n; i++) {
			Ux[i] = u;
			Uy[i] = 0.0;
		}

		jnl_face_interp_cds(mesh, Ux, ux_face);
		jnl_face_interp_cds(mesh, Uy, uy_face);
		jnl_bc_dirichlet_face_const(mesh, ux_face, "west", u);
		jnl_bc_dirichlet_face_const(mesh, ux_face, "east", u);
		jnl_bc_dirichlet_face_const(mesh, ux_face, "north", 0.0);
		jnl_bc_dirichlet_face_const(mesh, ux_face, "south", 0.0);
		jnl_bc_dirichlet_face_const(mesh, uy_face, "west", 0.0);
		jnl_bc_dirichlet_face_const(mesh, uy_face, "east", 0.0);
		jnl_bc_dirichlet_face_const(mesh, uy_face, "north", 0.0);
		jnl_bc_dirichlet_face_const(mesh, uy_face, "south", 0.0);
		jnl_face_normal_component(mesh, ux_face, uy_face, un_face);

		jnl_fvsys_reset(p.sys);
		jnl_laplacian_const(p.sys, mesh, gamma);
		jnl_div_cds_const(p.sys, mesh, rho, un_face);
		jnl_bc_dirichlet_const(p.sys, mesh, "west", 0.0);
		jnl_bc_dirichlet_const(p.sys, mesh, "east", 1.0);
		jnl_bc_neumann_const(p.sys, mesh, "north", 0.0);
		jnl_bc_neumann_const(p.sys, mesh, "south", 0.0);
		jnl_fvsys_solve_bicgstab(p.sys, p.ctx->cell_pool, p.T, 1e-12, 500);

		f64 sum = 0.0;
		for (i32 i = 0; i < p.n; i++) {
			f64 x = mesh->geom.cell_cx[i];
			f64 exact = (exp(Pe * x / L) - 1.0) / (exp_Pe - 1.0);
			f64 e = p.T[i] - exact;
			sum += e * e * mesh->geom.cell_vol[i];
		}
		errors[run] = sqrt(sum);
		free_problem(&p); // frees mesh too
	}

	f64 rate = log(errors[0] / errors[1]) / log(2.0);
	TEST_ASSERT_MSG(rate > 1.8,
	                "conv_diff_cds: rate=%.2f < 1.8, errors: %.2e -> %.2e",
	                rate, errors[0], errors[1]);
	printf("PASS test_conv_diff_cds (rate=%.2f, errors: %.2e -> %.2e)\n", rate,
	       errors[0], errors[1]);
}

// ============================================================
// Test 5: Convection-diffusion UDS — monotonicity + loose accuracy
// ============================================================
static void test_conv_diff_uds(void)
{
	// UDS needs the face flux array — allocate it in the ctx arena
	// via a face_field, and fill manually from mesh geometry
	problem p = make_problem(make_mesh(), 0, 1, 1);
	const f64 gamma = 1.0, rho_u = 10.0;

	f64 *un_face = jnl_fvm_ctx_alloc_face_field(p.ctx);
	i32 n_faces = p.mesh->topo.n_faces;
	for (i32 f = 0; f < n_faces; f++)
		un_face[f] = p.mesh->geom.face_nx[f] > 0.5 ? rho_u : 0.0;

	jnl_laplacian_const(p.sys, p.mesh, gamma);
	jnl_div_uds_const(p.sys, p.mesh, 1.0, un_face);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "west", 1.0);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "east", 0.0);
	jnl_fvsys_solve_bicgstab(p.sys, p.ctx->cell_pool, p.T, 1e-12, 0);

	// bounded
	TEST_ASSERT_MSG(p.T[0] <= 1.0 + 1e-6 && p.T[0] >= 0.0,
	                "conv_diff_uds: T[0]=%.6f out of bounds", p.T[0]);
	TEST_ASSERT_MSG(p.T[p.n - 1] >= -1e-6 && p.T[p.n - 1] <= 1.0,
	                "conv_diff_uds: T[n-1]=%.6f out of bounds", p.T[p.n - 1]);

	// monotone west->east
	for (i32 i = 1; i < p.n; i++)
		TEST_ASSERT_MSG(p.T[i] <= p.T[i - 1] + 1e-6,
		                "conv_diff_uds: non-monotone at %d: T=%.6f > T=%.6f", i,
		                p.T[i], p.T[i - 1]);

	// loose pointwise accuracy
	f64 exp_Pe = exp(rho_u * L / gamma);
	for (i32 i = 0; i < p.n; i++) {
		f64 x = p.mesh->geom.cell_cx[i];
		f64 exact = 1.0 - (exp(rho_u * x / gamma) - 1.0) / (exp_Pe - 1.0);
		f64 err = fabs(p.T[i] - exact);
		TEST_ASSERT_MSG(
		    err < 0.1,
		    "conv_diff_uds: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e", i, x,
		    p.T[i], exact, err);
	}

	free_problem(&p);
	printf("PASS test_conv_diff_uds\n");
}

// ============================================================
// Test 6: Two-region diffusion with field gamma
// Analytical: piecewise linear, flux-continuous
// ============================================================
static void test_diffusion_field_gamma(void)
{
	// 1 cell field for gamma, no face fields, 1 system
	problem p = make_problem(make_mesh(), 1, 0, 1);
	const f64 gamma_L = 1.0, gamma_R = 10.0, x_mid = 0.5 * L;

	f64 *gamma = jnl_fvm_ctx_alloc_field(p.ctx);
	for (i32 i = 0; i < p.n; i++)
		gamma[i] = p.mesh->geom.cell_cx[i] < x_mid ? gamma_L : gamma_R;

	jnl_laplacian_field(p.sys, p.mesh, gamma);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "west", 0.0);
	jnl_bc_dirichlet_const(p.sys, p.mesh, "east", 1.0);
	jnl_fvsys_solve_cg(p.sys, p.ctx->cell_pool, p.T, 1e-12, 0);

	f64 q = 1.0 / (x_mid / gamma_L + (L - x_mid) / gamma_R);
	for (i32 i = 0; i < p.n; i++) {
		f64 x = p.mesh->geom.cell_cx[i];
		f64 exact = x < x_mid ? q * x / gamma_L
		                      : q * x_mid / gamma_L + q * (x - x_mid) / gamma_R;
		f64 err = fabs(p.T[i] - exact);
		TEST_ASSERT_MSG(
		    err < 1e-2,
		    "diffusion_field_gamma: cell %d x=%.4f T=%.6f exact=%.6f err=%.2e",
		    i, x, p.T[i], exact, err);
	}

	free_problem(&p);
	printf("PASS test_diffusion_field_gamma\n");
}

// ============================================================
// Test 7: Matrix properties — no solver needed, raw arena is fine
// ============================================================
static void test_matrix_properties(void)
{
	struct jnl_mesh *mesh = make_mesh();
	i32 n = mesh->topo.n_cells;
	i32 n_conn = mesh->topo.n_faces;

	jnl_arena *arena = arena_create(jnl_fvsys_arena_size(n, n_conn));
	struct jnl_fvsys *sys =
	    jnl_fvsys_new(n, n_conn, mesh->topo.owner, mesh->topo.neighbour, arena);

	jnl_laplacian_const(sys, mesh, 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "west", 1.0);
	jnl_bc_dirichlet_const(sys, mesh, "east", 0.0);

	TEST_ASSERT_MSG(jnl_fvsys_all_diagonals_positive(sys),
	                "matrix_properties: non-positive diagonal");
	TEST_ASSERT_MSG(jnl_fvsys_diagonal_dominance(sys) >= 1.0,
	                "matrix_properties: dominance ratio %.4f < 1",
	                jnl_fvsys_diagonal_dominance(sys));
	TEST_ASSERT_MSG(
	    jnl_fvsys_max_asymmetry(sys) < 1e-12,
	    "matrix_properties: asymmetry %.2e (diffusion should be symmetric)",
	    jnl_fvsys_max_asymmetry(sys));

	arena_destroy(arena);
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
