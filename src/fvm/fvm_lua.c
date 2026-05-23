#include <lauxlib.h>
#include <string.h>

#include "lua_bindings.h"
#include "mesh2d.h"

#include "fvm/ctx.h"
#include "fvm/operators.h"
#include "fvm/bc.h"
#include "fvm/field.h"

#define CTX_MT "jnl.fvm.ctx"
#define FVSYS_MT "jnl.fvm.fvsys"

//
// FVSys userdata
//

typedef struct {
	struct jnl_fvsys *sys;
	struct jnl_scratch_pool *pool; // borrowed from ctx
	int ctx_ref;
} lua_fvsys;

static lua_fvsys *check_fvsys(lua_State *L, int idx)
{
	return (lua_fvsys *)luaL_checkudata(L, idx, FVSYS_MT);
}

static int l_fvsys_tostring(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_pushfstring(L, "fvsys(n_cells=%d, n_conns=%d)", s->sys->matrix.n_cells,
	                s->sys->matrix.n_conns);
	return 1;
}

static int l_fvsys_reset(lua_State *L)
{
	jnl_fvsys_reset(check_fvsys(L, 1)->sys);
	return 0;
}

static int l_fvsys_under_relax(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *v = check_vec(L, 2);
	f64 alpha = luaL_checknumber(L, 3);
	jnl_fvsys_under_relax(s->sys, v->data, alpha);
	return 0;
}

static int l_fvsys_pin_cell(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	i32 cell = (i32)luaL_checkinteger(L, 2) - 1;
	f64 val = luaL_checknumber(L, 3);
	jnl_fvsys_pin_cell(s->sys, cell, val);
	return 0;
}

static int l_fvsys_residual_norm(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	lua_pushnumber(L, jnl_fvsys_residual_norm(s->sys, x->data));
	return 1;
}

static int l_fvsys_solve_cg(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	struct jnl_solve_result result;
	result = jnl_fvsys_solve_cg(s->sys, s->pool, x->data, tol, max_iters);
	push_scratch_vec(L, result.x, s->sys->matrix.n_cells);
	lua_pushinteger(L, result.iters);
	return 2;
}

static int l_fvsys_solve_cg_into(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	i32 iters =
	    jnl_fvsys_solve_cg_into(s->sys, s->pool, x->data, tol, max_iters);
	lua_pushinteger(L, iters);
	return 1;
}

static int l_fvsys_solve_bicgstab(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	struct jnl_solve_result result;
	result = jnl_fvsys_solve_bicgstab(s->sys, s->pool, x->data, tol, max_iters);
	push_scratch_vec(L, result.x, s->sys->matrix.n_cells);
	lua_pushinteger(L, result.iters);
	return 2;
}

static int l_fvsys_solve_bicgstab_into(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_vec *x = check_vec(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	i32 iters =
	    jnl_fvsys_solve_bicgstab_into(s->sys, s->pool, x->data, tol, max_iters);
	lua_pushinteger(L, iters);
	return 1;
}

static int l_fvsys_diag_vec(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	push_owned_vec(L, s->sys->matrix.diag, s->sys->matrix.n_cells, 1);
	return 1;
}

static int l_fvsys_gc(lua_State *L)
{
	luaL_unref(L, LUA_REGISTRYINDEX, check_fvsys(L, 1)->ctx_ref);
	return 0;
}

static const luaL_Reg fvsys_mt[] = {
    {"reset", l_fvsys_reset},
    {"under_relax", l_fvsys_under_relax},
    {"pin_cell", l_fvsys_pin_cell},
    {"residual_norm", l_fvsys_residual_norm},
    {"solve_cg", l_fvsys_solve_cg},
    {"solve_bicgstab", l_fvsys_solve_bicgstab},
    {"solve_cg_into", l_fvsys_solve_cg_into},
    {"solve_bicgstab_into", l_fvsys_solve_bicgstab_into},
    {"diag_vec", l_fvsys_diag_vec},
    {"__tostring", l_fvsys_tostring},
    {"__gc", l_fvsys_gc},
    {NULL, NULL}};

//
// Ctx userdata
//

typedef struct {
	struct jnl_fvm_ctx *ctx;
} lua_fvm_ctx_ud;

static lua_fvm_ctx_ud *check_ctx(lua_State *L, int idx)
{
	return (lua_fvm_ctx_ud *)luaL_checkudata(L, idx, CTX_MT);
}

static int l_ctx_field(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	push_owned_vec(L, jnl_fvm_ctx_alloc_field(lc->ctx), lc->ctx->n_cells, 1);
	return 1;
}

static int l_ctx_face_field(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	push_owned_vec(L, jnl_fvm_ctx_alloc_face_field(lc->ctx), lc->ctx->n_faces,
	               1);
	return 1;
}

static int l_ctx_fvsys(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	lua_fvsys *ls = lua_newuserdata(L, sizeof(lua_fvsys));
	ls->sys = jnl_fvm_ctx_alloc_fvsys(lc->ctx);
	ls->pool = lc->ctx->cell_pool;
	lua_pushvalue(L, 1);
	ls->ctx_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	luaL_setmetatable(L, FVSYS_MT);
	return 1;
}

static int l_ctx_cell_pool(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	push_borrowed_pool(L, lc->ctx->cell_pool, 1);
	return 1;
}

static int l_ctx_face_pool(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	push_borrowed_pool(L, lc->ctx->face_pool, 1);
	return 1;
}

static int l_ctx_n_cells(lua_State *L)
{
	lua_pushinteger(L, check_ctx(L, 1)->ctx->n_cells);
	return 1;
}

static int l_ctx_n_faces(lua_State *L)
{
	lua_pushinteger(L, check_ctx(L, 1)->ctx->n_faces);
	return 1;
}

static int l_ctx_tostring(lua_State *L)
{
	struct jnl_fvm_ctx *c = check_ctx(L, 1)->ctx;
	lua_pushfstring(L, "fvm_ctx(n_cells=%d, n_faces=%d)", c->n_cells,
	                c->n_faces);
	return 1;
}

static int l_ctx_gc(lua_State *L)
{
	jnl_fvm_ctx_free(check_ctx(L, 1)->ctx);
	return 0;
}

static const luaL_Reg ctx_mt[] = {{"field", l_ctx_field},
                                  {"face_field", l_ctx_face_field},
                                  {"cell_pool", l_ctx_cell_pool},
                                  {"n_cells", l_ctx_n_cells},
                                  {"n_faces", l_ctx_n_faces},
                                  {"face_pool", l_ctx_face_pool},
                                  {"fvsys", l_ctx_fvsys},
                                  {"__tostring", l_ctx_tostring},
                                  {"__gc", l_ctx_gc},
                                  {NULL, NULL}};

//
// Operators
//

// needed by all operators
static struct jnl_mesh *check_mesh(lua_State *L, int idx)
{
	return *(struct jnl_mesh **)luaL_checkudata(L, idx, MESH_MT);
}

//
// DDT
//

static int l_ddt_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	f64 dt = luaL_checknumber(L, 4);
	lua_vec *phi_old = check_vec(L, 5);
	jnl_ddt_const(s->sys, m, rho, dt, phi_old->data);
	return 0;
}

static int l_ddt_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *rho = check_vec(L, 3);
	f64 dt = luaL_checknumber(L, 4);
	lua_vec *phi_old = check_vec(L, 5);
	jnl_ddt_field(s->sys, m, rho->data, dt, phi_old->data);
	return 0;
}

//
// Laplacian
//

static int l_laplacian_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 gamma = luaL_checknumber(L, 3);
	jnl_laplacian_const(s->sys, m, gamma);
	return 0;
}

static int l_laplacian_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *gamma = check_vec(L, 3);
	jnl_laplacian_field(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_field_harmonic(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *gamma = check_vec(L, 3);
	jnl_laplacian_field_harmonic(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_nonorth_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 gamma = luaL_checknumber(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	jnl_laplacian_nonorth_const(s->sys, m, gamma, gx->data, gy->data);
	return 0;
}

static int l_laplacian_nonorth_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *gamma = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	jnl_laplacian_nonorth_field(s->sys, m, gamma->data, gx->data, gy->data);
	return 0;
}

//
// Div CDS
//

static int l_div_cds_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_vec *un = check_vec(L, 4);
	jnl_div_cds_const(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_cds_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *rho = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);
	jnl_div_cds_field(s->sys, m, rho->data, un->data);
	return 0;
}

//
// Div UDS
//

static int l_div_uds_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_vec *un = check_vec(L, 4);
	jnl_div_uds_const(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_uds_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *rho = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);
	jnl_div_uds_field(s->sys, m, rho->data, un->data);
	return 0;
}

//
// Div TVD Correctors
//

static int l_div_tvd_minmod(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *phi = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	lua_vec *un = check_vec(L, 6);
	jnl_div_tvd_correction_minmod(s->sys, m, phi->data, gx->data, gy->data,
	                              un->data);
	return 0;
}

static int l_div_tvd_van_leer(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *phi = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	lua_vec *un = check_vec(L, 6);
	jnl_div_tvd_correction_van_leer(s->sys, m, phi->data, gx->data, gy->data,
	                                un->data);
	return 0;
}

static int l_div_tvd_superbee(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *phi = check_vec(L, 3);
	lua_vec *gx = check_vec(L, 4);
	lua_vec *gy = check_vec(L, 5);
	lua_vec *un = check_vec(L, 6);
	jnl_div_tvd_correction_superbee(s->sys, m, phi->data, gx->data, gy->data,
	                                un->data);
	return 0;
}

//
// Su
//

static int l_su_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 coeff = luaL_checknumber(L, 3);
	jnl_su_const(s->sys, m, coeff);
	return 0;
}

static int l_su_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *f = check_vec(L, 3);
	jnl_su_field(s->sys, m, f->data);
	return 0;
}

static int l_su_integrated(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *f = check_vec(L, 3);
	jnl_su_integrated(s->sys, m, f->data);
	return 0;
}

static int l_su_field_scaled(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 coeff = luaL_checknumber(L, 3);
	lua_vec *f = check_vec(L, 4);
	jnl_su_field_scaled(s->sys, m, coeff, f->data);
	return 0;
}

//
// Sp
//

static int l_sp_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 coeff = luaL_checknumber(L, 3);
	jnl_sp_const(s->sys, m, coeff);
	return 0;
}

static int l_sp_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *f = check_vec(L, 3);
	jnl_sp_field(s->sys, m, f->data);
	return 0;
}

static int l_sp_integrated(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_vec *f = check_vec(L, 3);
	jnl_sp_integrated(s->sys, m, f->data);
	return 0;
}

//
// Boundary Conditions
//

static int l_bc_dirichlet_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	const char *patch = luaL_checkstring(L, 3);
	f64 val = luaL_checknumber(L, 4);
	jnl_bc_dirichlet_const(s->sys, m, patch, val);
	return 0;
}

static int l_bc_neumann_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	const char *patch = luaL_checkstring(L, 3);
	f64 flux = luaL_checknumber(L, 4);
	jnl_bc_neumann_const(s->sys, m, patch, flux);
	return 0;
}

static int l_bc_dirichlet_face_const(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *face_f = check_vec(L, 2);
	const char *patch = luaL_checkstring(L, 3);
	f64 val = luaL_checknumber(L, 4);
	jnl_bc_dirichlet_face_const(m, face_f->data, patch, val);
	return 0;
}

static int l_bc_neumann_face_const(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *field = check_vec(L, 2);
	lua_vec *face_f = check_vec(L, 3);
	const char *patch = luaL_checkstring(L, 4);
	f64 flux = luaL_checknumber(L, 5);
	jnl_bc_neumann_face_const(m, field->data, face_f->data, patch, flux);
	return 0;
}

static int l_bc_dirichlet_face_normal(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *un = check_vec(L, 2);
	const char *patch = luaL_checkstring(L, 3);
	f64 ux = luaL_checknumber(L, 4);
	f64 uy = luaL_checknumber(L, 5);
	jnl_bc_dirichlet_face_normal(m, un->data, patch, ux, uy);
	return 0;
}

static int l_bc_neumann_face_normal(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *ux_f = check_vec(L, 2);
	lua_vec *uy_f = check_vec(L, 3);
	lua_vec *un = check_vec(L, 4);
	const char *patch = luaL_checkstring(L, 5);
	f64 ux_flux = luaL_checknumber(L, 6);
	f64 uy_flux = luaL_checknumber(L, 7);
	jnl_bc_neumann_face_normal(m, ux_f->data, uy_f->data, un->data, patch,
	                           ux_flux, uy_flux);
	return 0;
}

//
// Interpolation
//

static int l_face_interp_cds(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *field = check_vec(L, 2);
	lua_vec *face_field = check_vec(L, 3);
	jnl_face_interp_cds(m, field->data, face_field->data);
	return 0;
}

static int l_face_normal_component(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *ux_face = check_vec(L, 2);
	lua_vec *uy_face = check_vec(L, 3);
	lua_vec *un_face = check_vec(L, 4);
	jnl_face_normal_component(m, ux_face->data, uy_face->data, un_face->data);
	return 0;
}

static int l_rhie_chow(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *ux = check_vec(L, 2);
	lua_vec *uy = check_vec(L, 3);
	lua_vec *p = check_vec(L, 4);
	lua_vec *grad_px = check_vec(L, 5);
	lua_vec *grad_py = check_vec(L, 6);
	lua_vec *ap_x = check_vec(L, 7);
	lua_vec *ap_y = check_vec(L, 8);
	lua_vec *un_face = check_vec(L, 9);
	jnl_rhie_chow(m, ux->data, uy->data, p->data, grad_px->data, grad_py->data,
	              ap_x->data, ap_y->data, un_face->data);
	return 0;
}

//
// Gradient reconstruction
//

static int l_grad_green_gauss(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *face_field = check_vec(L, 2);
	lua_vec *grad_x = check_vec(L, 3);
	lua_vec *grad_y = check_vec(L, 4);
	jnl_grad_green_gauss(m, face_field->data, grad_x->data, grad_y->data);
	return 0;
}

//
// Misc
//

static int l_divergence(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *un_face = check_vec(L, 2);
	lua_vec *div = check_vec(L, 3);
	jnl_divergence(m, un_face->data, div->data);
	return 0;
}

static int l_vorticity_2d(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_vec *grad_vy_x = check_vec(L, 2);
	lua_vec *grad_ux_y = check_vec(L, 3);
	lua_vec *omega = check_vec(L, 4);
	jnl_vorticity_2d(m, grad_vy_x->data, grad_ux_y->data, omega->data);
	return 0;
}

//
// Module Open
//

// fvm.ctx_new(mesh, n_fields, n_systems) -> ctx
static int l_ctx_new(lua_State *L)
{
	struct jnl_mesh *mesh = *(struct jnl_mesh **)luaL_checkudata(L, 1, MESH_MT);
	i32 n_fields = (i32)luaL_checkinteger(L, 2);
	i32 n_face_fields = (i32)luaL_checkinteger(L, 3);
	i32 n_systems = (i32)luaL_checkinteger(L, 4);
	i32 n_cell_scratch = (i32)luaL_optinteger(L, 5, LINALG_MIN_SCRATCH);
	i32 n_face_scratch = (i32)luaL_optinteger(L, 6, 4);

	lua_fvm_ctx_ud *lc = lua_newuserdata(L, sizeof(lua_fvm_ctx_ud));
	lc->ctx = jnl_fvm_ctx_new(mesh, n_fields, n_face_fields, n_systems,
	                          n_cell_scratch, n_face_scratch);
	if (!lc->ctx) {
		return luaL_error(L, "fvm_ctx allocation failed");
	}
	luaL_setmetatable(L, CTX_MT);
	return 1;
}

static const luaL_Reg fvm_funcs[] = {
    {"ctx_new", l_ctx_new},
    // operators
    {"ddt_const", l_ddt_const},
    {"ddt_field", l_ddt_field},
    {"laplacian_const", l_laplacian_const},
    {"laplacian_field", l_laplacian_field},
    {"laplacian_field_harmonic", l_laplacian_field_harmonic},
    {"laplacian_nonorth_const", l_laplacian_nonorth_const},
    {"laplacian_nonorth_field", l_laplacian_nonorth_field},
    {"div_cds_const", l_div_cds_const},
    {"div_cds_field", l_div_cds_field},
    {"div_uds_const", l_div_uds_const},
    {"div_uds_field", l_div_uds_field},
    {"div_tvd_minmod", l_div_tvd_minmod},
    {"div_tvd_van_leer", l_div_tvd_van_leer},
    {"div_tvd_superbee", l_div_tvd_superbee},
    {"su_const", l_su_const},
    {"su_field", l_su_field},
    {"su_integrated", l_su_integrated},
    {"su_field_scaled", l_su_field_scaled},
    {"sp_const", l_sp_const},
    {"sp_field", l_sp_field},
    {"sp_integrated", l_sp_integrated},
    // bcs
    {"bc_dirichlet_const", l_bc_dirichlet_const},
    {"bc_neumann_const", l_bc_neumann_const},
    {"bc_dirichlet_face_const", l_bc_dirichlet_face_const},
    {"bc_neumann_face_const", l_bc_neumann_face_const},
    {"bc_dirichlet_face_normal", l_bc_dirichlet_face_normal},
    {"bc_neumann_face_normal", l_bc_neumann_face_normal},
    // interp
    {"face_interp_cds", l_face_interp_cds},
    {"face_normal_component", l_face_normal_component},
    {"rhie_chow", l_rhie_chow},
    // grad
    {"grad_green_gauss", l_grad_green_gauss},
    // misc
    {"divergence", l_divergence},
    {"vorticity_2d", l_vorticity_2d},
    {NULL, NULL}};

int luaopen_fvm_internal(lua_State *L)
{
	// Ensure VEC_MT is registered - idempotent
	luaL_requiref(L, "jnl.vec_internal", luaopen_vec_internal, 0);
	lua_pop(L, 1);

	// Ensure POOL_MT is registered - ditto
	luaL_requiref(L, "jnl.scratch_internal", luaopen_scratch_internal, 0);
	lua_pop(L, 1);

	// FVSYS_MT
	luaL_newmetatable(L, FVSYS_MT);
	luaL_setfuncs(L, fvsys_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	// CTX_MT
	luaL_newmetatable(L, CTX_MT);
	luaL_setfuncs(L, ctx_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newlib(L, fvm_funcs);
	return 1;
}
