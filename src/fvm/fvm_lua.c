#include <string.h>
#include <math.h>

#include "lua_bindings.h"
#include "mesh2d.h"

#include "fvm/ctx.h"
#include "fvm/operators.h"
#include "fvm/bc.h"
#include "fvm/interp.h"

#define CTX_MT "jnl.fvm.ctx"
#define FIELD_MT "jnl.fvm.field"
#define FVSYS_MT "jnl.fvm.fvsys"

//
// Anchor helper for child GC
//

static int anchor_ctx(lua_State *L, int ctx_idx)
{
	lua_pushvalue(L, ctx_idx);
	return luaL_ref(L, LUA_REGISTRYINDEX);
}

//
// Field userdata
//

typedef struct {
	f64 *data;
	i32 len;
	int ctx_ref;
} lua_field;

static lua_field *check_field(lua_State *L, int idx)
{
	return (lua_field *)luaL_checkudata(L, idx, FIELD_MT);
}

static int l_field_index(lua_State *L)
{
	if (lua_type(L, 2) == LUA_TNUMBER) {
		lua_field *f = check_field(L, 1);
		i32 i = (i32)lua_tointeger(L, 2) - 1;
		luaL_argcheck(L, i >= 0 && i < f->len, 2, "field index out of range");
		lua_pushnumber(L, f->data[i]);
		return 1;
	}
	// fall through to method table
	luaL_getmetatable(L, FIELD_MT);
	lua_pushvalue(L, 2);
	lua_rawget(L, -2);
	return 1;
}

static int l_field_newindex(lua_State *L)
{
	lua_field *f = check_field(L, 1);
	i32 i = (i32)luaL_checkinteger(L, 2) - 1;
	luaL_argcheck(L, i >= 0 && i < f->len, 2, "field index out of range");
	f->data[i] = luaL_checknumber(L, 3);
	return 0;
}

static int l_field_len(lua_State *L)
{
	lua_pushinteger(L, check_field(L, 1)->len);
	return 1;
}

static int l_field_tostring(lua_State *L)
{
	lua_field *f = check_field(L, 1);
	lua_pushfstring(L, "field(len=%d, data=%p)", f->len, f->data);
	return 1;
}

static int l_field_fill(lua_State *L)
{
	lua_field *f = check_field(L, 1);
	f64 val = luaL_checknumber(L, 2);
	for (i32 i = 0; i < f->len; i++)
		f->data[i] = val;
	return 0;
}

static int l_field_copy_from(lua_State *L)
{
	lua_field *dst = check_field(L, 1);
	lua_field *src = check_field(L, 2);
	luaL_argcheck(L, dst->len == src->len, 2, "field size mismatch");
	memcpy(dst->data, src->data, dst->len * sizeof(f64));
	return 0;
}

static int l_field_norm(lua_State *L)
{
	lua_field *f = check_field(L, 1);
	f64 s = 0.0;
	for (i32 i = 0; i < f->len; i++)
		s += f->data[i] * f->data[i];
	lua_pushnumber(L, sqrt(s));
	return 1;
}

static int l_field_gc(lua_State *L)
{
	lua_field *f = check_field(L, 1);
	luaL_unref(L, LUA_REGISTRYINDEX, f->ctx_ref);
	return 0;
}

// all methods + metamethods in one table; __index handled separately below
static const luaL_Reg field_mt[] = {
    {"fill", l_field_fill}, {"copy_from", l_field_copy_from},
    {"norm", l_field_norm}, {"__newindex", l_field_newindex},
    {"__len", l_field_len}, {"__tostring", l_field_tostring},
    {"__gc", l_field_gc},   {NULL, NULL}};

//
// FVSys userdata
//

typedef struct {
	struct jnl_fvsys *sys;
	struct jnl_solver_ctx *solver;
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
	lua_field *f = check_field(L, 2);
	f64 alpha = luaL_checknumber(L, 3);
	jnl_fvsys_under_relax(s->sys, f->data, alpha);
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
	lua_field *x = check_field(L, 2);
	lua_pushnumber(L, jnl_fvsys_residual_norm(s->sys, x->data));
	return 1;
}

static int l_fvsys_solve_cg(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_field *x = check_field(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	i32 iters = jnl_fvsys_solve_cg(s->sys, s->solver, x->data, tol, max_iters);
	lua_pushinteger(L, iters);
	return 1;
}

static int l_fvsys_solve_bicgstab(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	lua_field *x = check_field(L, 2);
	f64 tol = luaL_optnumber(L, 3, 1e-6);
	i32 max_iters = (i32)luaL_optinteger(L, 4, 1000);

	i32 iters =
	    jnl_fvsys_solve_bicgstab(s->sys, s->solver, x->data, tol, max_iters);
	lua_pushinteger(L, iters);
	return 1;
}

static int l_fvsys_gc(lua_State *L)
{
	luaL_unref(L, LUA_REGISTRYINDEX, check_fvsys(L, 1)->ctx_ref);
	return 0;
}

static const luaL_Reg fvsys_mt[] = {{"reset", l_fvsys_reset},
                                    {"under_relax", l_fvsys_under_relax},
                                    {"pin_cell", l_fvsys_pin_cell},
                                    {"residual_norm", l_fvsys_residual_norm},
                                    {"solve_cg", l_fvsys_solve_cg},
                                    {"solve_bicgstab", l_fvsys_solve_bicgstab},
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
	lua_field *lf = lua_newuserdata(L, sizeof(lua_field));
	lf->data = jnl_fvm_ctx_alloc_field(lc->ctx);
	lf->len = lc->ctx->n_cells;
	lf->ctx_ref = anchor_ctx(L, 1);
	luaL_setmetatable(L, FIELD_MT);
	return 1;
}

static int l_ctx_face_field(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	lua_field *lf = lua_newuserdata(L, sizeof(lua_field));
	lf->data = jnl_fvm_ctx_alloc_face_field(lc->ctx);
	lf->len = lc->ctx->n_faces;
	lf->ctx_ref = anchor_ctx(L, 1);
	luaL_setmetatable(L, FIELD_MT);
	return 1;
}

static int l_ctx_fvsys(lua_State *L)
{
	lua_fvm_ctx_ud *lc = check_ctx(L, 1);
	lua_fvsys *ls = lua_newuserdata(L, sizeof(lua_fvsys));
	ls->sys = jnl_fvm_ctx_alloc_fvsys(lc->ctx);
	ls->solver = lc->ctx->solver;
	ls->ctx_ref = anchor_ctx(L, 1);
	luaL_setmetatable(L, FVSYS_MT);
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

static const luaL_Reg ctx_mt[] = {
    {"field", l_ctx_field}, {"face_field", l_ctx_face_field},
    {"fvsys", l_ctx_fvsys}, {"__tostring", l_ctx_tostring},
    {"__gc", l_ctx_gc},     {NULL, NULL}};

//
// Operators
//

// needed by all operators
static struct jnl_mesh *check_mesh(lua_State *L, int idx)
{
	return *(struct jnl_mesh **)luaL_checkudata(L, idx, MESH_MT);
}

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
	lua_field *gamma = check_field(L, 3);
	jnl_laplacian_field(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_field_harmonic(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_field *gamma = check_field(L, 3);
	jnl_laplacian_field_harmonic(s->sys, m, gamma->data);
	return 0;
}

static int l_laplacian_nonorth_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 gamma = luaL_checknumber(L, 3);
	lua_field *gx = check_field(L, 4);
	lua_field *gy = check_field(L, 5);
	jnl_laplacian_nonorth_const(s->sys, m, gamma, gx->data, gy->data);
	return 0;
}

static int l_laplacian_nonorth_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_field *gamma = check_field(L, 3);
	lua_field *gx = check_field(L, 4);
	lua_field *gy = check_field(L, 5);
	jnl_laplacian_nonorth_field(s->sys, m, gamma->data, gx->data, gy->data);
	return 0;
}

static int l_div_cds_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_field *un = check_field(L, 4);
	jnl_div_cds_const(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_cds_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_field *rho = check_field(L, 3);
	lua_field *un = check_field(L, 4);
	jnl_div_cds_field(s->sys, m, rho->data, un->data);
	return 0;
}

static int l_div_uds_const(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 rho = luaL_checknumber(L, 3);
	lua_field *un = check_field(L, 4);
	jnl_div_uds_const(s->sys, m, rho, un->data);
	return 0;
}

static int l_div_uds_field(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_field *rho = check_field(L, 3);
	lua_field *un = check_field(L, 4);
	jnl_div_uds_field(s->sys, m, rho->data, un->data);
	return 0;
}

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
	lua_field *f = check_field(L, 3);
	jnl_su_field(s->sys, m, f->data);
	return 0;
}

static int l_su_integrated(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_field *f = check_field(L, 3);
	jnl_su_integrated(s->sys, m, f->data);
	return 0;
}

static int l_su_field_scaled(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	f64 coeff = luaL_checknumber(L, 3);
	lua_field *f = check_field(L, 4);
	jnl_su_field_scaled(s->sys, m, coeff, f->data);
	return 0;
}

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
	lua_field *f = check_field(L, 3);
	jnl_sp_field(s->sys, m, f->data);
	return 0;
}

static int l_sp_integrated(lua_State *L)
{
	lua_fvsys *s = check_fvsys(L, 1);
	struct jnl_mesh *m = check_mesh(L, 2);
	lua_field *f = check_field(L, 3);
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
	lua_field *face_f = check_field(L, 2);
	const char *patch = luaL_checkstring(L, 3);
	f64 val = luaL_checknumber(L, 4);
	jnl_bc_dirichlet_face_const(m, face_f->data, patch, val);
	return 0;
}

static int l_bc_neumann_face_const(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_field *field = check_field(L, 2);
	lua_field *face_f = check_field(L, 3);
	const char *patch = luaL_checkstring(L, 4);
	f64 flux = luaL_checknumber(L, 5);
	jnl_bc_neumann_face_const(m, field->data, face_f->data, patch, flux);
	return 0;
}

static int l_bc_dirichlet_face_normal(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_field *un = check_field(L, 2);
	const char *patch = luaL_checkstring(L, 3);
	f64 ux = luaL_checknumber(L, 4);
	f64 uy = luaL_checknumber(L, 5);
	jnl_bc_dirichlet_face_normal(m, un->data, patch, ux, uy);
	return 0;
}

static int l_bc_neumann_face_normal(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_field *ux_f = check_field(L, 2);
	lua_field *uy_f = check_field(L, 3);
	lua_field *un = check_field(L, 4);
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
	lua_field *field = check_field(L, 2);
	lua_field *face_field = check_field(L, 3);
	jnl_face_interp_cds(m, field->data, face_field->data);
	return 0;
}

static int l_face_normal_component(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_field *ux_face = check_field(L, 2);
	lua_field *uy_face = check_field(L, 3);
	lua_field *un_face = check_field(L, 4);
	jnl_face_normal_component(m, ux_face->data, uy_face->data, un_face->data);
	return 0;
}

static int l_rhie_chow(lua_State *L)
{
	struct jnl_mesh *m = check_mesh(L, 1);
	lua_field *ux = check_field(L, 2);
	lua_field *uy = check_field(L, 3);
	lua_field *p = check_field(L, 4);
	lua_field *grad_px = check_field(L, 5);
	lua_field *grad_py = check_field(L, 6);
	lua_field *ap_x = check_field(L, 7);
	lua_field *ap_y = check_field(L, 8);
	lua_field *un_face = check_field(L, 9);
	jnl_rhie_chow(m, ux->data, uy->data, p->data, grad_px->data, grad_py->data,
	              ap_x->data, ap_y->data, un_face->data);
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

	lua_fvm_ctx_ud *lc = lua_newuserdata(L, sizeof(lua_fvm_ctx_ud));
	lc->ctx = jnl_fvm_ctx_new(mesh, n_fields, n_face_fields, n_systems);
	if (!lc->ctx) {
		return luaL_error(L, "fvm_ctx allocation failed");
	}
	luaL_setmetatable(L, CTX_MT);
	return 1;
}

static const luaL_Reg fvm_funcs[] = {
    {"ctx_new", l_ctx_new},
    // operators
    {"laplacian_const", l_laplacian_const},
    {"laplacian_field", l_laplacian_field},
    {"laplacian_field_harmonic", l_laplacian_field_harmonic},
    {"laplacian_nonorth_const", l_laplacian_nonorth_const},
    {"laplacian_nonorth_field", l_laplacian_nonorth_field},
    {"div_cds_const", l_div_cds_const},
    {"div_cds_field", l_div_cds_field},
    {"div_uds_const", l_div_uds_const},
    {"div_uds_field", l_div_uds_field},
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
    {NULL, NULL}};

static void register_mt(lua_State *L, const char *name, const luaL_Reg *methods,
                        lua_CFunction index_fn)
{
	luaL_newmetatable(L, name);
	luaL_setfuncs(L, methods, 0);
	if (index_fn) {
		lua_pushcfunction(L, index_fn);
		lua_setfield(L, -2, "__index");
	} else {
		// simple __index = self
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
	lua_pop(L, 1);
}

int luaopen_fvm_internal(lua_State *L)
{
	register_mt(L, FIELD_MT, field_mt, l_field_index); // custom dispatch
	register_mt(L, FVSYS_MT, fvsys_mt, NULL);          // __index = self
	register_mt(L, CTX_MT, ctx_mt, NULL);              // __index = self

	luaL_newlib(L, fvm_funcs);
	return 1;
}
