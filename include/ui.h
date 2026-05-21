#ifndef JNL_UI_H
#define JNL_UI_H

#include "geo2d.h"

typedef struct jnl_ui_handle jnl_ui_handle;

jnl_ui_handle *jnl_ui_spawn(void);

int jnl_ui_send_pslg(jnl_ui_handle *, struct jnl_pslg *);
void jnl_ui_close(jnl_ui_handle *);
void jnl_ui_free(jnl_ui_handle *);

#endif
