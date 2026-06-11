#ifndef JNL_UI_H
#define JNL_UI_H

#include "geo2d/domain2d.h"
#include "mesh2d.h"

typedef struct jnl_ui_handle jnl_ui_handle;

jnl_ui_handle *jnl_ui_spawn(void);

int jnl_ui_closed(jnl_ui_handle *);

//
// Geometry
//

int jnl_ui_send_domain(jnl_ui_handle *h, const struct jnl_domain2d *d);

int jnl_ui_send_mesh(jnl_ui_handle *h, const pmsh2d *mesh);

//
// Field updates
//

int jnl_ui_set_field(jnl_ui_handle *h, const char *name, const f64 *data,
                     u32 n);

int jnl_ui_set_vector(jnl_ui_handle *h, const char *name, const char *field_x,
                      const char *field_y);

int jnl_ui_view_field(jnl_ui_handle *h, const char *name);

int jnl_ui_view_mesh(jnl_ui_handle *h, bool show);

//
// Lifecycle
//

int jnl_ui_focus(jnl_ui_handle *);
void jnl_ui_close(jnl_ui_handle *);
void jnl_ui_free(jnl_ui_handle *);

#endif
