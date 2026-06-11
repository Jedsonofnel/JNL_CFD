#include <getopt.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <readline/history.h>
#include <readline/readline.h>

#include "lua_bindings.h"

#ifndef LUA_ASSET_PATH
#define LUA_ASSET_PATH "../lua"
#endif

//
// Ctrl-C / cancellation / REPL state
//

static volatile sig_atomic_t jnl_cancel_requested = 0;
static volatile sig_atomic_t jnl_force_cancel_requested = 0;
static volatile sig_atomic_t jnl_in_readline = 0;
static volatile sig_atomic_t jnl_readline_jmp_active = 0;

static int jnl_repl_started = 0;

static sigjmp_buf jnl_readline_jmp;

static void clear_cancel_state(void)
{
	jnl_cancel_requested = 0;
	jnl_force_cancel_requested = 0;
}

static void jnl_handle_sigint(int signo)
{
	(void)signo;

	/*
	 * At the prompt, Ctrl-C abandons the current readline call.
	 * The non-signal context then clears the visible terminal line.
	 */
	if (jnl_in_readline && jnl_readline_jmp_active) {
		siglongjmp(jnl_readline_jmp, 1);
	}

	/*
	 * During evaluation, the first Ctrl-C requests cooperative
	 * cancellation. A second Ctrl-C arms the Lua instruction hook,
	 * which raises an ordinary Lua error at the next hook boundary.
	 */
	if (!jnl_cancel_requested) {
		jnl_cancel_requested = 1;
	} else {
		jnl_force_cancel_requested = 1;
	}
}

static int install_signal_handlers(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = jnl_handle_sigint;
	sigemptyset(&sa.sa_mask);

	/*
	 * Do not use SA_RESTART. Blocking terminal input should be
	 * interruptible by Ctrl-C.
	 */
	sa.sa_flags = 0;

	if (sigaction(SIGINT, &sa, NULL) != 0) {
		perror("sigaction");
		return 0;
	}

	return 1;
}

static void jnl_force_cancel_hook(lua_State *L, lua_Debug *ar)
{
	(void)ar;

	if (!jnl_force_cancel_requested) {
		return;
	}

	clear_cancel_state();
	luaL_error(L, "forced cancellation after second Ctrl-C");
}

static int l_repl_cancel_seen(lua_State *L)
{
	lua_pushboolean(L, jnl_cancel_requested != 0);
	return 1;
}

static int l_repl_cancel_clear(lua_State *L)
{
	(void)L;

	clear_cancel_state();
	return 0;
}

static int l_repl_mark_started(lua_State *L)
{
	(void)L;

	jnl_repl_started = 1;
	return 0;
}

//
// Helpers
//

static void set_lua_path(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "path");

	const char *existing = lua_tostring(L, -1);

	lua_pushfstring(L,
	                LUA_ASSET_PATH "/?.lua;" LUA_ASSET_PATH "/?/init.lua;"
	                               "%s",
	                existing ? existing : "");

	/*
	 * Stack before remove:
	 *
	 *     package, old_path, new_path
	 */
	lua_remove(L, -2);
	lua_setfield(L, -2, "path");
	lua_pop(L, 1);
}

static void usage(const char *prog)
{
	fprintf(
	    stderr,
	    "usage: %s [options] [script.lua|script.fnl]\n"
	    "\n"
	    "options:\n"
	    "  -r, --repl    start the REPL after the script, or immediately\n"
	    "                when no script is supplied\n"
	    "  -l, --llm     print the complete LLM coding context and API\n"
	    "                reference\n"
	    "  -h, --help    show this help\n"
	    "\n"
	    "inside the REPL:\n"
	    "  ,help         show commands and registered values\n"
	    "  ,doc          list documented modules\n"
	    "  ,llm          print the complete LLM coding context\n"
	    "  ,quit         exit the REPL\n"
	    "  Ctrl-D        exit the REPL\n"
	    "\n"
	    "Ctrl-C clears the prompt. During evaluation, press once to request\n"
	    "cooperative cancellation and twice to force a Lua cancellation.\n",
	    prog);
}

static const char *lua_error_string(lua_State *L)
{
	const char *message = lua_tostring(L, -1);
	return message ? message : "(non-string Lua error)";
}

static int run_lua_chunk(lua_State *L, const char *source, const char *context)
{
	if (luaL_dostring(L, source) == LUA_OK) {
		lua_settop(L, 0);
		return 1;
	}

	fprintf(stderr, "%s: %s\n", context, lua_error_string(L));
	lua_settop(L, 0);
	return 0;
}

static int run_lua_script(lua_State *L, const char *path)
{
	if (luaL_dofile(L, path) == LUA_OK) {
		lua_settop(L, 0);
		return 1;
	}

	fprintf(stderr, "error running Lua script: %s\n", lua_error_string(L));
	lua_settop(L, 0);
	return 0;
}

static int run_fennel_script(lua_State *L, const char *path)
{
	lua_getglobal(L, "require");
	lua_pushstring(L, "fennel");

	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		fprintf(stderr, "error loading Fennel: %s\n", lua_error_string(L));
		lua_settop(L, 0);
		return 0;
	}

	/*
	 * Stack:
	 *
	 *     fennel_module
	 */
	lua_getfield(L, -1, "dofile");
	lua_pushstring(L, path);

	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		fprintf(stderr, "error running Fennel script: %s\n",
		        lua_error_string(L));
		lua_settop(L, 0);
		return 0;
	}

	lua_pop(L, 1);
	lua_settop(L, 0);
	return 1;
}

static int run_script(lua_State *L, const char *path)
{
	const char *ext = strrchr(path, '.');

	if (ext && strcmp(ext, ".lua") == 0) {
		return run_lua_script(L, path);
	}

	if (ext && strcmp(ext, ".fnl") == 0) {
		return run_fennel_script(L, path);
	}

	fprintf(stderr, "error: script must be a .lua or .fnl file\n");
	return 0;
}

//
// Readline
//

static void clear_terminal_line(void)
{
	/*
	 * Readline already assumes an interactive terminal. Erase the entire
	 * current line and return the cursor to its first column before Lua
	 * requests the next prompt.
	 */
	static const char erase_line[] = "\r\033[2K";

	(void)write(STDOUT_FILENO, erase_line, sizeof(erase_line) - 1);
}

static int l_readline(lua_State *L)
{
	const char *prompt = luaL_optstring(L, 1, "");

	clear_cancel_state();
	jnl_in_readline = 1;

	if (sigsetjmp(jnl_readline_jmp, 1) != 0) {
		jnl_readline_jmp_active = 0;
		jnl_in_readline = 0;

		/*
		 * We did not return normally through readline, so release its
		 * transient line state and restore the terminal.
		 */
		rl_free_line_state();
		rl_cleanup_after_signal();

		clear_terminal_line();
		fflush(stdout);

		clear_cancel_state();

		/*
		 * Lua treats the interrupted prompt as a blank line and asks
		 * readline for a fresh prompt.
		 */
		lua_pushstring(L, "");
		return 1;
	}

	jnl_readline_jmp_active = 1;
	char *line = readline(prompt);
	jnl_readline_jmp_active = 0;
	jnl_in_readline = 0;

	if (!line) {
		lua_pushnil(L);
		return 1;
	}

	if (*line) {
		add_history(line);
	}

	lua_pushstring(L, line);
	free(line);
	return 1;
}

//
// Main
//

int main(int argc, char **argv)
{
	const char *script = NULL;
	int want_repl = 0;
	int want_llm = 0;

	static const struct option long_options[] = {
	    {"repl", no_argument, NULL, 'r'},
	    {"llm", no_argument, NULL, 'l'},
	    {"help", no_argument, NULL, 'h'},
	    {NULL, 0, NULL, 0},
	};

	opterr = 0;

	for (;;) {
		int option = getopt_long(argc, argv, "rlh", long_options, NULL);

		if (option == -1) {
			break;
		}

		switch (option) {
		case 'r':
			want_repl = 1;
			break;

		case 'l':
			want_llm = 1;
			break;

		case 'h':
			usage(argv[0]);
			return EXIT_SUCCESS;

		case '?':
		default:
			fprintf(stderr, "unknown option: %s\n", argv[optind - 1]);
			usage(argv[0]);
			return EXIT_FAILURE;
		}
	}

	if (optind < argc) {
		script = argv[optind++];
	}

	if (optind < argc) {
		fprintf(stderr, "too many script arguments\n");
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	if (!script && !want_repl && !want_llm) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	lua_State *L = luaL_newstate();

	if (!L) {
		fprintf(stderr, "failed to create Lua state\n");
		return EXIT_FAILURE;
	}

	luaL_openlibs(L);
	set_lua_path(L);
	register_preloaders(L);

	/*
	 * Readline must not install or re-raise its own SIGINT handler. The
	 * host owns Ctrl-C so Lua code can cooperate with cancellation.
	 */
	rl_instream = stdin;
	rl_outstream = stdout;
	rl_catch_signals = 0;
	rl_catch_sigwinch = 0;

	if (!install_signal_handlers()) {
		lua_close(L);
		return EXIT_FAILURE;
	}

	/*
	 * The hook is normally almost free: it tests one sig_atomic_t flag
	 * every 1000 Lua VM instructions. It raises only after the second
	 * Ctrl-C received before cancellation state is cleared.
	 */
	lua_sethook(L, jnl_force_cancel_hook, LUA_MASKCOUNT, 1000);

	lua_pushcfunction(L, l_readline);
	lua_setglobal(L, "readline");

	lua_pushcfunction(L, l_repl_cancel_seen);
	lua_setglobal(L, "__jnl_repl_cancel_seen");

	lua_pushcfunction(L, l_repl_cancel_clear);
	lua_setglobal(L, "__jnl_repl_cancel_clear");

	lua_pushcfunction(L, l_repl_mark_started);
	lua_setglobal(L, "__jnl_repl_mark_started");

	if (script) {
		lua_pushstring(L, script);
		lua_setglobal(L, "_script");

		if (!run_script(L, script)) {
			lua_close(L);
			return EXIT_FAILURE;
		}
	}

	if (want_llm) {
		const char *boot = "local llm = require('jnl.doc.llm')\n"
		                   "io.write(llm.context_string({ width = 88 }))\n";

		if (!run_lua_chunk(L, boot, "error generating LLM context")) {
			lua_close(L);
			return EXIT_FAILURE;
		}

		if (!want_repl) {
			lua_close(L);
			return EXIT_SUCCESS;
		}
	}

	if (want_repl && !jnl_repl_started) {
		const char *boot = "local repl = require('jnl.repl').new()\n"
		                   "repl:run()\n";

		if (!run_lua_chunk(L, boot, "error starting REPL")) {
			lua_close(L);
			return EXIT_FAILURE;
		}
	}

	lua_close(L);
	return EXIT_SUCCESS;
}
