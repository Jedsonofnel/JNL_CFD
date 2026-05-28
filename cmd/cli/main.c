#include <stdlib.h>
#include <setjmp.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <readline/readline.h>
#include <readline/history.h>

#include "lua_bindings.h"

#ifndef LUA_ASSET_PATH
#define LUA_ASSET_PATH "../lua" // fallback default
#endif

//
// Ctrl-C / cancellation / REPL state
//

static volatile sig_atomic_t jnl_sigint_seen = 0;
static volatile sig_atomic_t jnl_in_readline = 0;
static volatile sig_atomic_t jnl_readline_jmp_active = 0;

static int jnl_repl_started = 0;

static sigjmp_buf jnl_readline_jmp;

static void jnl_handle_sigint(int signo)
{
	(void)signo;

	jnl_sigint_seen = 1;

	if (jnl_in_readline && jnl_readline_jmp_active) {
		siglongjmp(jnl_readline_jmp, 1);
	}
}

static void install_signal_handlers(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = jnl_handle_sigint;
	sigemptyset(&sa.sa_mask);

	/*
	 * Do not use SA_RESTART: we want blocking terminal input to be
	 * interrupted by Ctrl-C so readline can return control to Lua.
	 */
	sa.sa_flags = 0;

	sigaction(SIGINT, &sa, NULL);
}

static int l_repl_cancel_seen(lua_State *L)
{
	lua_pushboolean(L, jnl_sigint_seen != 0);
	return 1;
}

static int l_repl_cancel_clear(lua_State *L)
{
	(void)L;

	jnl_sigint_seen = 0;
	return 0;
}

static int l_repl_mark_started(lua_State *L)
{
	(void)L;
	jnl_repl_started = 1;
	return 0;
}

static int l_repl_was_started(lua_State *L)
{
	lua_pushboolean(L, jnl_repl_started);
	return 1;
}

//
// Helpers
//

static void set_lua_path(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_pushstring(L, LUA_ASSET_PATH "/?.lua;" LUA_ASSET_PATH "/?/init.lua");
	lua_setfield(L, -2, "path");
	lua_pop(L, 1);
}

static void usage(const char *prog)
{
	fprintf(
	    stderr,
	    "usage: %s [--repl] [--llm] [script.lua|script.fnl]\n"
	    "\n"
	    "  script.lua   run a Lua script\n"
	    "  script.fnl   run a Fennel script\n"
	    "  --repl       start the REPL after the script, or immediately if\n"
	    "               no script is given\n"
	    "  --llm        print full LLM coding context and API reference\n"
	    "\n"
	    "  Inside the REPL: ,help  ,doc  ,llm  ,quit  ctrl-D\n",
	    prog);
}

//
// readline
//

static int l_readline(lua_State *L)
{
	const char *prompt = luaL_optstring(L, 1, "");

	jnl_sigint_seen = 0;
	jnl_in_readline = 1;
	jnl_readline_jmp_active = 1;

	if (sigsetjmp(jnl_readline_jmp, 1) != 0) {
		jnl_readline_jmp_active = 0;
		jnl_in_readline = 0;
		jnl_sigint_seen = 0;

		rl_free_line_state();
		rl_cleanup_after_signal();

		lua_pushstring(L, "");
		return 1;
	}

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

	// arg parsing
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--repl") == 0) {
			want_repl = 1;
		} else if (strcmp(argv[i], "--llm") == 0) {
			want_llm = 1;
		} else if (strcmp(argv[i], "--help") == 0 ||
		           strcmp(argv[i], "-h") == 0) {
			usage(argv[0]);
			return EXIT_SUCCESS;
		} else if (argv[i][0] == '-') {
			fprintf(stderr, "unknown option: %s\n", argv[i]);
			usage(argv[0]);
			return EXIT_FAILURE;
		} else if (!script) {
			script = argv[i];
		} else {
			fprintf(stderr, "too many arguments\n");
			usage(argv[0]);
			return EXIT_FAILURE;
		}
	}

	if (!script && !want_repl && !want_llm) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	// Lua initialisation
	lua_State *L = luaL_newstate();
	if (!L) {
		fprintf(stderr, "failed to create Lua state\n");
		return EXIT_FAILURE;
	}

	luaL_openlibs(L);
	set_lua_path(L);
	register_preloaders(L);

	/*
	 * Let the host program own Ctrl-C. Readline's default signal handling
	 * can re-raise SIGINT and kill the process before Lua can cooperate.
	 */
	rl_instream = stdin;
	rl_outstream = stdout;
	rl_catch_signals = 0;
	rl_catch_sigwinch = 0;
	install_signal_handlers();

	lua_pushcfunction(L, l_readline);
	lua_setglobal(L, "readline");

	lua_pushcfunction(L, l_repl_cancel_seen);
	lua_setglobal(L, "__jnl_repl_cancel_seen");

	lua_pushcfunction(L, l_repl_cancel_clear);
	lua_setglobal(L, "__jnl_repl_cancel_clear");

	lua_pushcfunction(L, l_repl_mark_started);
	lua_setglobal(L, "__jnl_repl_mark_started");

	lua_pushcfunction(L, l_repl_was_started);
	lua_setglobal(L, "__jnl_repl_was_started");

	// run user script
	if (script) {
		const char *ext = strrchr(script, '.');

		int is_fennel = ext && strcmp(ext, ".fnl") == 0;
		int is_lua = ext && strcmp(ext, ".lua") == 0;

		lua_pushstring(L, script);
		lua_setglobal(L, "_script");

		if (is_fennel) {
			lua_getglobal(L, "require");
			lua_pushstring(L, "fennel");

			if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
				fprintf(stderr, "error loading fennel: %s\n",
				        lua_tostring(L, -1));
				lua_close(L);
				return EXIT_FAILURE;
			}

			lua_getfield(L, -1, "dofile");
			lua_pushstring(L, script);

			if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
				fprintf(stderr, "error running fennel script: %s\n",
				        lua_tostring(L, -1));
				lua_close(L);
				return EXIT_FAILURE;
			}

			lua_pop(L, 1); // fennel module
		} else if (is_lua) {
			if (luaL_dofile(L, script) != LUA_OK) {
				fprintf(stderr, "error running script: %s\n",
				        lua_tostring(L, -1));
				lua_close(L);
				return EXIT_FAILURE;
			}
		} else {
			fprintf(stderr, "error: script must be a .lua or .fnl file\n");
			lua_close(L);
			return EXIT_FAILURE;
		}
	}

	// LLM context dump
	if (want_llm) {
		const char *boot = "local llm = require('jnl.llm')\n"
		                   "io.write(llm.context_string({ width = 88 }))\n";

		if (luaL_dostring(L, boot) != LUA_OK) {
			fprintf(stderr, "error generating LLM context: %s\n",
			        lua_tostring(L, -1));
			lua_close(L);
			return EXIT_FAILURE;
		}

		if (!want_repl) {
			lua_close(L);
			return EXIT_SUCCESS;
		}
	}

	// bare REPL
	if (want_repl && !jnl_repl_started) {
		const char *boot = "local REPL = require('jnl.repl')\n"
		                   "local repl = REPL.new()\n"
		                   "repl:run()\n";

		if (luaL_dostring(L, boot) != LUA_OK) {
			fprintf(stderr, "error starting REPL: %s\n", lua_tostring(L, -1));
			lua_close(L);
			return EXIT_FAILURE;
		}
	}

	lua_close(L);
	return EXIT_SUCCESS;
}
