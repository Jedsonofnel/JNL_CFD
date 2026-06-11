#ifndef JNL_UI_MSG_H
#define JNL_UI_MSG_H

#include "ui_internal.h"
#include "geo2d/domain2d.h"

//
// Parent -> wire (called from handle.c)
//

int ui_msg_send_close(int fd);
int ui_msg_send_focus(int fd);
int ui_msg_send_domain2d(int fd, const struct jnl_domain2d *d);

// Stubs — not yet implemented, return 0.
int ui_msg_send_set_mesh(int fd, const void *mesh);
int ui_msg_send_set_field(int fd, const char *name, const double *data,
                          unsigned n);
int ui_msg_send_set_vector(int fd, const char *name, const char *fx,
                           const char *fy);
int ui_msg_send_view_field(int fd, const char *name);
int ui_msg_send_view_mesh(int fd, int show);

//
// Wire -> child state (called from window.c)
//

// Read one message from fd, update ws, return message type or -1 on error.
int ui_msg_recv(int fd, struct jnl_ui_window_state *ws);

// Release all curves in a domain (does NOT free the chains array itself).
void ui_domain_free(struct jnl_ui_domain *d);

#endif // JNL_UI_MSG_H
