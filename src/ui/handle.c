#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/prctl.h>

#include "ui.h"
#include "handle.h"
#include "msg.h"
#include "window.h"
#include "jnl/common.h"

//
// Handle helpers
//

void ui_handle_close_fd(struct jnl_ui_handle *h)
{
	if (!h || h->sock_fd < 0)
		return;
	close(h->sock_fd);
	h->sock_fd = -1;
}

void ui_handle_reap_nonblocking(struct jnl_ui_handle *h)
{
	if (!h || h->reaped || h->pid <= 0)
		return;
	int status;
	pid_t r = waitpid(h->pid, &status, WNOHANG);
	if (r == h->pid || (r < 0 && errno == ECHILD)) {
		h->reaped = 1;
		h->closed = 1;
		ui_handle_close_fd(h);
	}
}

void ui_handle_mark_closed(struct jnl_ui_handle *h)
{
	if (!h)
		return;
	h->closed = 1;
	ui_handle_close_fd(h);
	ui_handle_reap_nonblocking(h);
}

//
// Public API
//

jnl_ui_handle *jnl_ui_spawn(void)
{
	signal(SIGPIPE, SIG_IGN);

	int sv[2];
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0)
		return NULL;

	pid_t pid = fork();
	if (pid < 0) {
		close(sv[0]);
		close(sv[1]);
		return NULL;
	}

	if (pid == 0) {
		close(sv[0]);
#ifdef __linux__
		prctl(PR_SET_PDEATHSIG, SIGTERM);
#endif
		ui_window_run(sv[1]);
		// never returns
	}

	close(sv[1]);

	jnl_ui_handle *h = malloc(sizeof *h);
	if (!h) {
		close(sv[0]);
		kill(pid, SIGTERM);
		return NULL;
	}

	h->pid = pid;
	h->sock_fd = sv[0];
	h->closed = 0;
	h->reaped = 0;
	return h;
}

int jnl_ui_closed(jnl_ui_handle *h)
{
	if (!h)
		return 1;
	if (h->closed || h->sock_fd < 0) {
		h->closed = 1;
		return 1;
	}

	ui_handle_reap_nonblocking(h);
	if (h->closed)
		return 1;

	struct pollfd pfd = {.fd = h->sock_fd, .events = POLLOUT};
	int r = poll(&pfd, 1, 0);
	if (r < 0 || (r > 0 && (pfd.revents & (POLLHUP | POLLERR | POLLNVAL)))) {
		ui_handle_mark_closed(h);
		return 1;
	}
	return 0;
}

int jnl_ui_send_domain(jnl_ui_handle *h, const struct jnl_domain2d *d)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_domain2d(h->sock_fd, d) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}

int jnl_ui_send_mesh(jnl_ui_handle *h, const pmsh2d *mesh)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_set_mesh(h->sock_fd, mesh) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}

int jnl_ui_focus(jnl_ui_handle *h)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_focus(h->sock_fd) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}

void jnl_ui_close(jnl_ui_handle *h)
{
	if (!h)
		return;
	if (!h->closed && h->sock_fd >= 0) {
		ui_msg_send_close(h->sock_fd);
		ui_handle_close_fd(h);
		h->closed = 1;
	}
	if (!h->reaped && h->pid > 0) {
		waitpid(h->pid, NULL, 0);
		h->reaped = 1;
	}
}

void jnl_ui_free(jnl_ui_handle *h)
{
	if (!h)
		return;
	jnl_ui_close(h);
	free(h);
}

int jnl_ui_set_field(jnl_ui_handle *h, const char *name, const f64 *data, u32 n)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_set_field(h->sock_fd, name, data, (unsigned)n) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}

int jnl_ui_set_vector(jnl_ui_handle *h, const char *name, const char *fx,
                      const char *fy)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_set_vector(h->sock_fd, name, fx, fy) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}

int jnl_ui_view_field(jnl_ui_handle *h, const char *name)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_view_field(h->sock_fd, name ? name : "") < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}

int jnl_ui_view_mesh(jnl_ui_handle *h, bool show)
{
	if (jnl_ui_closed(h))
		return -1;
	if (ui_msg_send_view_mesh(h->sock_fd, show ? 1 : 0) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}
	return 0;
}
