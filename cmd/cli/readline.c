#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <lauxlib.h>
#include <lua.h>

#include <readline/history.h>
#include <readline/readline.h>

#include "host.h"
#include "readline.h"

#define JNL_HISTORY_LIMIT 2000
#define JNL_LUA_HOOK_COUNT 1000

//
// Cancellation and REPL state
//

static volatile sig_atomic_t cancel_requested = 0;
static volatile sig_atomic_t force_cancel_requested = 0;
static volatile sig_atomic_t in_readline = 0;
static volatile sig_atomic_t readline_jump_active = 0;

static int repl_started = 0;

static sigjmp_buf readline_jump;

static void clear_cancel_state(void)
{
	cancel_requested = 0;
	force_cancel_requested = 0;
}

static void handle_sigint(int signo)
{
	(void)signo;

	/*
	 * At the prompt, abandon the active Readline call. Terminal restoration
	 * is performed after returning to normal execution through sigsetjmp().
	 */
	if (in_readline && readline_jump_active) {
		siglongjmp(readline_jump, 1);
	}

	/*
	 * During Lua evaluation, the first Ctrl-C requests cooperative
	 * cancellation. A second Ctrl-C asks the Lua instruction hook to raise
	 * an error at the next safe VM boundary.
	 */
	if (!cancel_requested) {
		cancel_requested = 1;
	} else {
		force_cancel_requested = 1;
	}
}

static int install_signal_handler(void)
{
	struct sigaction action;

	memset(&action, 0, sizeof(action));

	action.sa_handler = handle_sigint;
	action.sa_flags = 0;

	sigemptyset(&action.sa_mask);

	if (sigaction(SIGINT, &action, NULL) != 0) {
		return -1;
	}

	return 0;
}

static void force_cancel_hook(lua_State *L, lua_Debug *debug)
{
	(void)debug;

	if (!force_cancel_requested) {
		return;
	}

	clear_cancel_state();

	luaL_error(L, "forced cancellation after second Ctrl-C");
}

//
// Persistent history
//

static char history_path[JNL_HOST_PATH_CAP];
static int history_ready = 0;
static int shutdown_registered = 0;

static int create_history_file(const char *path)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);

	if (fd < 0) {
		return -1;
	}

	return close(fd);
}

static int initialise_history(void)
{
	if (history_ready) {
		return 0;
	}

	char state[JNL_HOST_PATH_CAP];
	char app[JNL_HOST_PATH_CAP];
	char repl[JNL_HOST_PATH_CAP];

	if (jnl_host_base_dir(JNL_HOST_DIR_STATE, state, sizeof(state)) != 0) {
		return -1;
	}

	if (jnl_host_path_join(app, sizeof(app), state, "jnl") != 0) {
		return -1;
	}

	if (jnl_host_path_join(repl, sizeof(repl), app, "repl") != 0) {
		return -1;
	}

	if (jnl_host_mkdir_p(repl) != 0) {
		return -1;
	}

	if (jnl_host_path_join(history_path, sizeof(history_path), repl,
	                       "history") != 0) {
		return -1;
	}

	if (create_history_file(history_path) != 0) {
		history_path[0] = '\0';
		return -1;
	}

	using_history();

	if (read_history(history_path) != 0) {
		history_path[0] = '\0';
		return -1;
	}

	stifle_history(JNL_HISTORY_LIMIT);

	history_ready = 1;

	if (!shutdown_registered) {
		if (atexit(jnl_cli_readline_shutdown) != 0) {
			history_ready = 0;
			history_path[0] = '\0';
			return -1;
		}

		shutdown_registered = 1;
	}

	return 0;
}

static void add_persistent_history(const char *line)
{
	if (!line || *line == '\0') {
		return;
	}

	add_history(line);

	if (!history_ready) {
		return;
	}

	/*
	 * Persist each accepted line immediately so abnormal termination loses
	 * as little history as possible.
	 */
	(void)append_history(1, history_path);
}

void jnl_cli_readline_shutdown(void)
{
	if (!history_ready) {
		return;
	}

	(void)history_truncate_file(history_path, JNL_HISTORY_LIMIT);

	history_ready = 0;
	history_path[0] = '\0';
}

//
// Terminal input
//

static void clear_terminal_line(void)
{
	static const char erase_line[] = "\r\033[2K";

	(void)write(STDOUT_FILENO, erase_line, sizeof(erase_line) - 1);
}

static int lua_readline(lua_State *L)
{
	const char *prompt = luaL_optstring(L, 1, "");

	clear_cancel_state();

	in_readline = 1;

	if (sigsetjmp(readline_jump, 1) != 0) {
		readline_jump_active = 0;
		in_readline = 0;

		/*
		 * Readline did not return normally, so discard its transient input
		 * state and restore the terminal before Lua requests a fresh prompt.
		 */
		rl_free_line_state();
		rl_cleanup_after_signal();

		clear_terminal_line();
		fflush(stdout);

		clear_cancel_state();

		/*
		 * An interrupted prompt behaves like an empty input line. The Lua
		 * REPL loop ignores it and calls readline() again.
		 */
		lua_pushstring(L, "");
		return 1;
	}

	readline_jump_active = 1;

	char *line = readline(prompt);

	readline_jump_active = 0;
	in_readline = 0;

	if (!line) {
		lua_pushnil(L);
		return 1;
	}

	if (*line) {
		add_persistent_history(line);
	}

	lua_pushstring(L, line);

	free(line);

	return 1;
}

//
// Lua host bridge
//

static int lua_cancel_seen(lua_State *L)
{
	lua_pushboolean(L, cancel_requested != 0);

	return 1;
}

static int lua_cancel_clear(lua_State *L)
{
	(void)L;

	clear_cancel_state();

	return 0;
}

static int lua_mark_repl_started(lua_State *L)
{
	(void)L;

	repl_started = 1;

	return 0;
}

static void install_lua_function(lua_State *L, const char *name,
                                 lua_CFunction function)
{
	lua_pushcfunction(L, function);
	lua_setglobal(L, name);
}

//
// Public API
//

int jnl_cli_readline_init(lua_State *L)
{
	if (!L) {
		errno = EINVAL;
		return -1;
	}

	/*
	 * The CLI owns SIGINT. Readline must not install or re-raise its own
	 * signal handlers.
	 */
	rl_instream = stdin;
	rl_outstream = stdout;
	rl_catch_signals = 0;
	rl_catch_sigwinch = 0;

	if (install_signal_handler() != 0) {
		return -1;
	}

	/*
	 * Persistent history is optional. The REPL remains usable when no
	 * suitable state directory is available.
	 */
	(void)initialise_history();

	clear_cancel_state();

	lua_sethook(L, force_cancel_hook, LUA_MASKCOUNT, JNL_LUA_HOOK_COUNT);

	install_lua_function(L, "readline", lua_readline);

	install_lua_function(L, "__jnl_repl_cancel_seen", lua_cancel_seen);

	install_lua_function(L, "__jnl_repl_cancel_clear", lua_cancel_clear);

	install_lua_function(L, "__jnl_repl_mark_started", lua_mark_repl_started);

	return 0;
}

int jnl_cli_repl_started(void) { return repl_started; }
