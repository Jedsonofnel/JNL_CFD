#ifndef JNL_UI_HANDLE_H
#define JNL_UI_HANDLE_H

#include <sys/types.h>

// Internal definition of the opaque handle declared in ui.h.
struct jnl_ui_handle {
	pid_t pid;
	int sock_fd;
	int closed;
	int reaped;
};

void ui_handle_close_fd(struct jnl_ui_handle *h);
void ui_handle_reap_nonblocking(struct jnl_ui_handle *h);
void ui_handle_mark_closed(struct jnl_ui_handle *h);

#endif // JNL_UI_HANDLE_H
