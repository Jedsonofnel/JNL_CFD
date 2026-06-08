#ifndef JNL_BC_H
#define JNL_BC_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

// NOTE: _d  = Dirichlet
// NOTE: _n  = Neumann
// NOTE: _r  = Robin (a*phi + b*dphi/dn = c)
// NOTE: _s  = scalar field
// NOTE: _v  = vector field (ux, uy)

typedef enum {
	JNL_BC_NEUMANN = 0,
	JNL_BC_DIRICHLET = 1,
	JNL_BC_ROBIN = 2,
} jnl_bc_kind;

struct jnl_bc_entry {
	const char *patch;
	jnl_bc_kind kind;

	f64 value; // Dirichlet value or Neumann normal gradient

	// Robin: a*phi_f + b*dphi/dn = c
	f64 a;
	f64 b;
	f64 c;
};

struct jnl_bc_set {
	const struct jnl_bc_entry *entries;
	i32 n_entries;

	jnl_bc_kind all_kind;
	f64 all_value;

	// Robin all-patch coefficients
	f64 all_a;
	f64 all_b;
	f64 all_c;
};

#define JNL_BC_SET(entries_, n_)                                               \
	{.entries = (entries_),                                                    \
	 .n_entries = (n_),                                                        \
	 .all_kind = JNL_BC_NEUMANN,                                               \
	 .all_value = 0.0,                                                         \
	 .all_a = 0.0,                                                             \
	 .all_b = 0.0,                                                             \
	 .all_c = 0.0}

#define JNL_BC_SET_ALL(kind_, value_)                                          \
	{.entries = NULL,                                                          \
	 .n_entries = 0,                                                           \
	 .all_kind = (kind_),                                                      \
	 .all_value = (value_),                                                    \
	 .all_a = 0.0,                                                             \
	 .all_b = 0.0,                                                             \
	 .all_c = 0.0}

#define JNL_BC_SET_ALL_R(a_, b_, c_)                                           \
	{.entries = NULL,                                                          \
	 .n_entries = 0,                                                           \
	 .all_kind = JNL_BC_ROBIN,                                                 \
	 .all_value = 0.0,                                                         \
	 .all_a = (a_),                                                            \
	 .all_b = (b_),                                                            \
	 .all_c = (c_)}

#define JNL_BC_D(patch_, v_)                                                   \
	{.patch = (patch_),                                                        \
	 .kind = JNL_BC_DIRICHLET,                                                 \
	 .value = (v_),                                                            \
	 .a = 0.0,                                                                 \
	 .b = 0.0,                                                                 \
	 .c = 0.0}

#define JNL_BC_N(patch_, v_)                                                   \
	{.patch = (patch_),                                                        \
	 .kind = JNL_BC_NEUMANN,                                                   \
	 .value = (v_),                                                            \
	 .a = 0.0,                                                                 \
	 .b = 0.0,                                                                 \
	 .c = 0.0}

#define JNL_BC_R(patch_, a_, b_, c_)                                           \
	{.patch = (patch_),                                                        \
	 .kind = JNL_BC_ROBIN,                                                     \
	 .value = 0.0,                                                             \
	 .a = (a_),                                                                \
	 .b = (b_),                                                                \
	 .c = (c_)}

//
// Scalar patch BCs
//

void jnl_patch_s_fill_d(const pmsh2d *mesh, f64 *phi, const char *patch,
                        f64 value);

void jnl_patch_s_fill_n(const pmsh2d *mesh, f64 *phi, const char *patch,
                        f64 grad_n);

void jnl_patch_s_fill_r(const pmsh2d *mesh, f64 *phi, const char *patch, f64 a,
                        f64 b, f64 c);

void jnl_patch_s_close_d(fvsys *sys, const pmsh2d *mesh, const char *patch,
                         f64 value);

void jnl_patch_s_close_n(fvsys *sys, const pmsh2d *mesh, const char *patch,
                         f64 grad_n);

void jnl_patch_s_close_r(fvsys *sys, const pmsh2d *mesh, const char *patch,
                         f64 a, f64 b, f64 c);

// BC set — applies all entries in one call
void jnl_bc_set_fill(const struct jnl_bc_set *bcs, const pmsh2d *mesh,
                     f64 *phi);

void jnl_bc_set_close(const struct jnl_bc_set *bcs, fvsys *sys,
                      const pmsh2d *mesh);

//
// Vector patch BCs
//

void jnl_patch_v_fill_d(const pmsh2d *mesh, f64 *ux, f64 *uy, const char *patch,
                        f64 ux_val, f64 uy_val);

void jnl_patch_v_fill_n(const pmsh2d *mesh, f64 *ux, f64 *uy, const char *patch,
                        f64 ux_gn, f64 uy_gn);

void jnl_patch_v_fill_nt(const pmsh2d *mesh, f64 *ux, f64 *uy,
                         const char *patch, jnl_bc_kind nkind, f64 nval,
                         jnl_bc_kind tkind, f64 tval);

//
// Scalar baffle-region BCs
//

void jnl_bregion_s_fill_d(const pmsh2d *mesh, f64 *phi, const char *baffle,
                          i32 region, f64 value);

void jnl_bregion_s_fill_n(const pmsh2d *mesh, f64 *phi, const char *baffle,
                          i32 region, f64 grad_n);

void jnl_bregion_s_fill_r(const pmsh2d *mesh, f64 *phi, const char *baffle,
                          i32 region, f64 a, f64 b, f64 c);

void jnl_bregion_s_close_d(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           i32 region, f64 value);

void jnl_bregion_s_close_n(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           i32 region, f64 grad_n);

void jnl_bregion_s_close_r(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           i32 region, f64 a, f64 b, f64 c);

//
// Vector baffle-region BCs
//

void jnl_bregion_v_fill_d(const pmsh2d *mesh, f64 *ux, f64 *uy,
                          const char *baffle, i32 region, f64 ux_val,
                          f64 uy_val);

void jnl_bregion_v_fill_n(const pmsh2d *mesh, f64 *ux, f64 *uy,
                          const char *baffle, i32 region, f64 ux_gn, f64 uy_gn);

void jnl_bregion_v_fill_nt(const pmsh2d *mesh, f64 *ux, f64 *uy,
                           const char *baffle, i32 region, jnl_bc_kind nkind,
                           f64 nval, jnl_bc_kind tkind, f64 tval);

//
// Whole-baffle scalar helpers
//

void jnl_baffle_s_fill_insul(const pmsh2d *mesh, f64 *phi, const char *baffle);

void jnl_baffle_s_fill_cont(const pmsh2d *mesh, f64 *phi, const char *baffle);

void jnl_baffle_s_close_insul(fvsys *sys, const pmsh2d *mesh,
                              const char *baffle);

void jnl_baffle_s_close_cont(fvsys *sys, const pmsh2d *mesh,
                             const char *baffle);

void jnl_baffle_s_close_cc(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           f64 conductance);

static inline void jnl_baffle_s_close_cr(fvsys *sys, const pmsh2d *mesh,
                                         const char *baffle, f64 resistance)
{
	jnl_baffle_s_close_cc(sys, mesh, baffle, 1.0 / resistance);
}

//
// All-baffles scalar helpers
//

void jnl_baffles_s_fill_insul(const pmsh2d *mesh, f64 *phi);

void jnl_baffles_s_close_insul(fvsys *sys, const pmsh2d *mesh);

//
// Whole-baffle vector helpers
//

void jnl_baffle_v_fill_cont(const pmsh2d *mesh, f64 *ux, f64 *uy,
                            const char *baffle);

//
// Debug
//

void jnl_bc_assert_all_closed(const fvsys *sys);

#endif // JNL_BC_H
