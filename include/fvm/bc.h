#ifndef JNL_BC_H
#define JNL_BC_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

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
// Scalar patch ghost filling
//

void jnl_patch_scalar_fill_dirichlet(const pmsh2d *mesh, f64 *phi,
                                     const char *patch_name, f64 value);

void jnl_patch_scalar_fill_neumann(const pmsh2d *mesh, f64 *phi,
                                   const char *patch_name, f64 grad_n);

void jnl_patch_scalar_fill_robin(const pmsh2d *mesh, f64 *phi,
                                 const char *patch_name, f64 a, f64 b, f64 c);

void jnl_bc_set_fill_ghosts(const struct jnl_bc_set *bcs, const pmsh2d *mesh,
                            f64 *phi);

//
// Scalar patch implicit closure
//

void jnl_patch_scalar_close_dirichlet(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                      const char *patch_name, f64 value);

void jnl_patch_scalar_close_neumann(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                    const char *patch_name, f64 grad_n);

void jnl_patch_scalar_close_robin(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                  const char *patch_name, f64 a, f64 b, f64 c);

void jnl_bc_set_close(const struct jnl_bc_set *bcs, struct jnl_fvsys *sys,
                      const pmsh2d *mesh);

//
// Scalar baffle-region ghost filling
//

void jnl_baffle_region_scalar_fill_dirichlet(const pmsh2d *mesh, f64 *phi,
                                             const char *baffle_name,
                                             i32 region_marker, f64 value);

void jnl_baffle_region_scalar_fill_neumann(const pmsh2d *mesh, f64 *phi,
                                           const char *baffle_name,
                                           i32 region_marker, f64 grad_n);

void jnl_baffle_region_scalar_fill_robin(const pmsh2d *mesh, f64 *phi,
                                         const char *baffle_name,
                                         i32 region_marker, f64 a, f64 b,
                                         f64 c);

//
// Scalar baffle-region implicit closure
//

void jnl_baffle_region_scalar_close_dirichlet(struct jnl_fvsys *sys,
                                              const pmsh2d *mesh,
                                              const char *baffle_name,
                                              i32 region_marker, f64 value);

void jnl_baffle_region_scalar_close_neumann(struct jnl_fvsys *sys,
                                            const pmsh2d *mesh,
                                            const char *baffle_name,
                                            i32 region_marker, f64 grad_n);

void jnl_baffle_region_scalar_close_robin(struct jnl_fvsys *sys,
                                          const pmsh2d *mesh,
                                          const char *baffle_name,
                                          i32 region_marker, f64 a, f64 b,
                                          f64 c);

//
// Whole scalar baffle helpers
//

void jnl_baffle_scalar_fill_insulated(const pmsh2d *mesh, f64 *phi,
                                      const char *baffle_name);

void jnl_baffle_scalar_close_insulated(struct jnl_fvsys *sys,
                                       const pmsh2d *mesh,
                                       const char *baffle_name);

void jnl_baffles_scalar_fill_insulated(const pmsh2d *mesh, f64 *phi);

void jnl_baffles_scalar_close_insulated(struct jnl_fvsys *sys,
                                        const pmsh2d *mesh);

void jnl_baffle_scalar_fill_continuous(const pmsh2d *mesh, f64 *phi,
                                       const char *baffle_name);

void jnl_baffle_scalar_close_continuous(struct jnl_fvsys *sys,
                                        const pmsh2d *mesh,
                                        const char *baffle_name);

void jnl_baffle_scalar_close_contact_conductance(struct jnl_fvsys *sys,
                                                 const pmsh2d *mesh,
                                                 const char *baffle_name,
                                                 f64 conductance);

void jnl_baffle_scalar_close_contact_resistance(struct jnl_fvsys *sys,
                                                const pmsh2d *mesh,
                                                const char *baffle_name,
                                                f64 resistance);

//
// Vector2 patch ghost filling
//

void jnl_patch_vector2_fill_dirichlet(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                      const char *patch_name, f64 ux_value,
                                      f64 uy_value);

void jnl_patch_vector2_fill_neumann(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                    const char *patch_name, f64 ux_grad_n,
                                    f64 uy_grad_n);

void jnl_patch_vector2_fill_zero_gradient(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                          const char *patch_name);

void jnl_patch_vector2_fill_no_slip(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                    const char *patch_name);

void jnl_patch_vector2_fill_moving_wall(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                        const char *patch_name, f64 ux_wall,
                                        f64 uy_wall);

void jnl_patch_vector2_fill_nt(const pmsh2d *mesh, f64 *ux, f64 *uy,
                               const char *patch_name, jnl_bc_kind normal_kind,
                               f64 normal_value, jnl_bc_kind tangential_kind,
                               f64 tangential_value);

void jnl_patch_vector2_fill_slip(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                 const char *patch_name);

void jnl_patch_vector2_fill_symmetry(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                     const char *patch_name);

//
// Vector2 baffle-region ghost filling
//

void jnl_baffle_region_vector2_fill_dirichlet(const pmsh2d *mesh, f64 *ux,
                                              f64 *uy, const char *baffle_name,
                                              i32 region_marker, f64 ux_value,
                                              f64 uy_value);

void jnl_baffle_region_vector2_fill_neumann(const pmsh2d *mesh, f64 *ux,
                                            f64 *uy, const char *baffle_name,
                                            i32 region_marker, f64 ux_grad_n,
                                            f64 uy_grad_n);

void jnl_baffle_region_vector2_fill_zero_gradient(const pmsh2d *mesh, f64 *ux,
                                                  f64 *uy,
                                                  const char *baffle_name,
                                                  i32 region_marker);

void jnl_baffle_region_vector2_fill_no_slip(const pmsh2d *mesh, f64 *ux,
                                            f64 *uy, const char *baffle_name,
                                            i32 region_marker);

void jnl_baffle_region_vector2_fill_moving_wall(const pmsh2d *mesh, f64 *ux,
                                                f64 *uy,
                                                const char *baffle_name,
                                                i32 region_marker, f64 ux_wall,
                                                f64 uy_wall);

void jnl_baffle_region_vector2_fill_nt(
    const pmsh2d *mesh, f64 *ux, f64 *uy, const char *baffle_name,
    i32 region_marker, jnl_bc_kind normal_kind, f64 normal_value,
    jnl_bc_kind tangential_kind, f64 tangential_value);

void jnl_baffle_region_vector2_fill_slip(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                         const char *baffle_name,
                                         i32 region_marker);

void jnl_baffle_region_vector2_fill_symmetry(const pmsh2d *mesh, f64 *ux,
                                             f64 *uy, const char *baffle_name,
                                             i32 region_marker);

void jnl_baffle_vector2_fill_continuous(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                        const char *baffle_name);

//
// Debug/safety
//

void jnl_bc_assert_all_closed(const struct jnl_fvsys *sys);

#endif // JNL_BC_H
