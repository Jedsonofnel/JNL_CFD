#include <string.h>

#include "jnl/test.h"
#include "fvm/ctx.h"
#include "fvm/linalg.h"
#include "mesh2d.h"

#define EPS 1e-12

static pmsh2d make_minimal_count_mesh(void)
{
	pmsh2d mesh;
	memset(&mesh, 0, sizeof(mesh));

	mesh.topo.n_cells = 5;
	mesh.topo.n_real_cells = 3;
	mesh.topo.n_faces = 7;
	mesh.topo.n_internal_faces = 2;

	return mesh;
}

static pmsh2d make_minimal_fvsys_mesh(void)
{
	pmsh2d mesh;
	memset(&mesh, 0, sizeof(mesh));

	mesh.topo.n_cells = 3;
	mesh.topo.n_real_cells = 3;
	mesh.topo.n_faces = 4;
	mesh.topo.n_internal_faces = 0;

	return mesh;
}

static void test_ctx_new_initialises_counts_and_scratch_pools(void)
{
	pmsh2d mesh = make_minimal_count_mesh();

	struct jnl_fvm_ctx *ctx = jnl_fvm_ctx_new(&mesh, 2, 3, 4, 1);

	NOT_NULL(ctx);
	EQ_PTR(ctx->mesh, &mesh);

	EQ_I32(ctx->n_cells, 5);
	EQ_I32(ctx->n_real_cells, 3);
	EQ_I32(ctx->n_faces, 7);
	EQ_I32(ctx->n_internal_faces, 2);

	NOT_NULL(ctx->arena);

	NOT_NULL(ctx->cell_scratch);
	NOT_NULL(ctx->real_scratch);
	NOT_NULL(ctx->face_scratch);

	EQ_I32(ctx->cell_scratch->len, ctx->n_cells);
	EQ_I32(ctx->real_scratch->len, ctx->n_real_cells);
	EQ_I32(ctx->face_scratch->len, ctx->n_faces);

	EQ_I32(jnl_scratch_capacity(ctx->cell_scratch), 0);
	EQ_I32(jnl_scratch_capacity(ctx->real_scratch), 0);
	EQ_I32(jnl_scratch_capacity(ctx->face_scratch), 0);

	jnl_fvm_ctx_free(ctx);
}

static void test_ctx_allocates_zeroed_persistent_fields(void)
{
	pmsh2d mesh = make_minimal_count_mesh();

	struct jnl_fvm_ctx *ctx = jnl_fvm_ctx_new(&mesh, 1, 1, 1, 0);
	NOT_NULL(ctx);

	f64 *cell = jnl_fvm_ctx_field(ctx);
	f64 *real = jnl_fvm_ctx_real_field(ctx);
	f64 *face = jnl_fvm_ctx_face_field(ctx);

	NOT_NULL(cell);
	NOT_NULL(real);
	NOT_NULL(face);

	for (i32 i = 0; i < ctx->n_cells; i++)
		NEAR_F64(cell[i], 0.0, EPS);

	for (i32 i = 0; i < ctx->n_real_cells; i++)
		NEAR_F64(real[i], 0.0, EPS);

	for (i32 i = 0; i < ctx->n_faces; i++)
		NEAR_F64(face[i], 0.0, EPS);

	jnl_fvm_ctx_free(ctx);
}

static void test_ctx_persistent_fields_are_independent(void)
{
	pmsh2d mesh = make_minimal_count_mesh();

	struct jnl_fvm_ctx *ctx = jnl_fvm_ctx_new(&mesh, 2, 2, 2, 0);
	NOT_NULL(ctx);

	f64 *a = jnl_fvm_ctx_field(ctx);
	f64 *b = jnl_fvm_ctx_field(ctx);

	f64 *ra = jnl_fvm_ctx_real_field(ctx);
	f64 *rb = jnl_fvm_ctx_real_field(ctx);

	f64 *fa = jnl_fvm_ctx_face_field(ctx);
	f64 *fb = jnl_fvm_ctx_face_field(ctx);

	NOT_NULL(a);
	NOT_NULL(b);
	NOT_NULL(ra);
	NOT_NULL(rb);
	NOT_NULL(fa);
	NOT_NULL(fb);

	CHECK(a != b);
	CHECK(ra != rb);
	CHECK(fa != fb);

	a[0] = 1.0;
	b[0] = 2.0;

	ra[0] = 3.0;
	rb[0] = 4.0;

	fa[0] = 5.0;
	fb[0] = 6.0;

	NEAR_F64(a[0], 1.0, EPS);
	NEAR_F64(b[0], 2.0, EPS);

	NEAR_F64(ra[0], 3.0, EPS);
	NEAR_F64(rb[0], 4.0, EPS);

	NEAR_F64(fa[0], 5.0, EPS);
	NEAR_F64(fb[0], 6.0, EPS);

	jnl_fvm_ctx_free(ctx);
}

static void test_ctx_scratch_grows_independently_of_persistent_arena(void)
{
	pmsh2d mesh = make_minimal_count_mesh();

	struct jnl_fvm_ctx *ctx = jnl_fvm_ctx_new(&mesh, 1, 1, 1, 0);
	NOT_NULL(ctx);

	f64 *persistent = jnl_fvm_ctx_real_field(ctx);
	NOT_NULL(persistent);

	persistent[0] = 123.0;

	f64 *scratch[12];

	for (i32 i = 0; i < 12; i++) {
		scratch[i] = jnl_scratch_acquire(ctx->real_scratch);
		NOT_NULL(scratch[i]);
		scratch[i][0] = (f64)i;
	}

	EQ_I32(jnl_scratch_capacity(ctx->real_scratch), 12);
	EQ_I32(jnl_scratch_in_use(ctx->real_scratch), 12);
	EQ_I32(jnl_scratch_high_water(ctx->real_scratch), 12);

	NEAR_F64(persistent[0], 123.0, EPS);

	jnl_scratch_reset(ctx->real_scratch);

	EQ_I32(jnl_scratch_capacity(ctx->real_scratch), 12);
	EQ_I32(jnl_scratch_in_use(ctx->real_scratch), 0);
	EQ_I32(jnl_scratch_high_water(ctx->real_scratch), 12);

	NEAR_F64(persistent[0], 123.0, EPS);

	jnl_fvm_ctx_free(ctx);
}

static void test_ctx_allocates_fvsys_with_expected_sizes(void)
{
	pmsh2d mesh = make_minimal_fvsys_mesh();

	struct jnl_fvm_ctx *ctx = jnl_fvm_ctx_new(&mesh, 0, 0, 0, 2);
	NOT_NULL(ctx);

	fvsys *a = jnl_fvm_ctx_fvsys(ctx);
	fvsys *b = jnl_fvm_ctx_fvsys(ctx);

	NOT_NULL(a);
	NOT_NULL(b);
	CHECK(a != b);

	EQ_I32(a->matrix.n_cells, mesh.topo.n_real_cells);
	EQ_I32(a->matrix.n_mesh_faces, mesh.topo.n_faces);
	EQ_I32(a->matrix.n_internal_faces, mesh.topo.n_internal_faces);

	EQ_I32(b->matrix.n_cells, mesh.topo.n_real_cells);
	EQ_I32(b->matrix.n_mesh_faces, mesh.topo.n_faces);
	EQ_I32(b->matrix.n_internal_faces, mesh.topo.n_internal_faces);

	NOT_NULL(a->matrix.diag);
	NOT_NULL(a->rhs);

	NOT_NULL(b->matrix.diag);
	NOT_NULL(b->rhs);

	jnl_fvm_ctx_free(ctx);
}

static void test_ctx_fvsys_memory_is_zeroed(void)
{
	pmsh2d mesh = make_minimal_fvsys_mesh();

	struct jnl_fvm_ctx *ctx = jnl_fvm_ctx_new(&mesh, 0, 0, 0, 1);
	NOT_NULL(ctx);

	fvsys *sys = jnl_fvm_ctx_fvsys(ctx);
	NOT_NULL(sys);

	for (i32 i = 0; i < sys->matrix.n_cells; i++) {
		NEAR_F64(sys->matrix.diag[i], 0.0, EPS);
		NEAR_F64(sys->rhs[i], 0.0, EPS);
	}

	for (i32 f = 0; f < sys->matrix.n_coupled_faces; f++) {
		NEAR_F64(sys->matrix.lower[f], 0.0, EPS);
		NEAR_F64(sys->matrix.upper[f], 0.0, EPS);
	}

	jnl_fvm_ctx_free(ctx);
}

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("ctx");

	JNL_TEST(&t, test_ctx_new_initialises_counts_and_scratch_pools);
	JNL_TEST(&t, test_ctx_allocates_zeroed_persistent_fields);
	JNL_TEST(&t, test_ctx_persistent_fields_are_independent);
	JNL_TEST(&t, test_ctx_scratch_grows_independently_of_persistent_arena);
	JNL_TEST(&t, test_ctx_allocates_fvsys_with_expected_sizes);
	JNL_TEST(&t, test_ctx_fvsys_memory_is_zeroed);

	return jnl_test_end(&t);
}
