#ifndef JNL_UI_H
#define JNL_UI_H

#include "geo2d.h"
#include "mesh2d.h"

typedef struct jnl_ui_handle jnl_ui_handle;

jnl_ui_handle *jnl_ui_spawn(void);

int jnl_ui_send_pslg(jnl_ui_handle *, struct jnl_pslg *);
int jnl_ui_send_mesh(jnl_ui_handle *h, struct jnl_mesh *mesh);

void jnl_ui_close(jnl_ui_handle *);
void jnl_ui_free(jnl_ui_handle *);

#endif
